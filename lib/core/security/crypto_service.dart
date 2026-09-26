import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors/app_exception.dart';

/// AES-256-GCM 口令加解密服务（W14）
///
/// 三条必须写下来的取舍，后人是必问的：
///
/// ① **口令不直接当 AES 密钥**。用户口令的熵远低于 256 位随机密钥，直接拿来
///    当 key 等于把破解成本降回"跑一遍字典"。这里用 PBKDF2-HMAC-SHA256
///    派生（10 万次迭代），并且**每次加密都用新的 16 字节随机盐**——同一个口令
///    在两个备份包里派生出的密钥不同，一个包被拖走不会连带另一个。
///
/// ② **容器自描述**：文件头记录 magic + 版本 + 盐长/IV 长/MAC 长。
///    解密时不靠"我记得参数是多少"，将来要升级迭代次数只需动版本字节，
///    老包照样能认出来、用老参数解开。
///
/// ③ **失败只有一种答案**：GCM 是 AEAD，它只回答"认证通过 / 不通过"。
///    密码填错、文件被截掉一半、被人改过一个字节——现象完全一样，
///    实现上没有办法区分（能区分的话就说明认证算法有问题了）。
///    所以 UI 文案统一是"密码不正确，或者这份数据已被改动过"。
///
/// 纯 Dart 实现（cryptography 无平台通道）：`flutter test` 里可直接跑真加解密。
class CryptoService {
  CryptoService({Cipher? algorithm, Pbkdf2? kdf, Random? random})
      : _algorithm = algorithm ?? AesGcm.with256bits(),
        _kdf = kdf ??
            Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: defaultIterations,
              bits: 256,
            ),
        _random = random ?? Random.secure();

  /// PBKDF2 迭代次数。
  /// 10 万是 NIST SP 800-132 建议量级下、纯 Dart 实现还能接受的值；
  /// （本机约 100–200ms；太长会让"解锁"和"导出"变成肉眼可见的卡顿）。
  /// 纯 Dart 实现下本机约 100–200ms；再往上加会让"解锁"和"导出"变成肉眼可见的
  /// 卡顿，而收益远小于口令本身变成 8 位以上随机串。测试注入低值即可，
  /// 不要为了让测试跑得快去调低生产默认值。
  ///
  /// ⚠️ **改这个值等于换一套密钥**：迭代次数参与派生，改完之后老密文一律解不开。
  /// 真要升级必须同时抬 [magic] 的版本字节、并在 `open()` 里按版本选参数——
  /// 默默改常量的后果是"老用户的应用锁与加密备份在一夜之间全部失效"。
  static const int defaultIterations = 100000;

  /// 盐长：128 位，与 PBKDF2 推荐的最小盐长一致
  static const int saltLength = 16;

  /// 文件头 magic（末位 `\x31` 是格式版本）
  static final List<int> magic = utf8.encode('PLSEC1');

  /// 文件头固定部分长度：magic + 盐长 + IV 长 + MAC 长
  static const int headerLength = 6 + 3;

  final Cipher _algorithm;
  final Pbkdf2 _kdf;
  final Random _random;

  /// 生成随机盐（每次加密一份新的，禁止复用）
  Uint8List newSalt() {
    final out = Uint8List(saltLength);
    for (var i = 0; i < saltLength; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// 由口令与盐派生密钥
  Future<SecretKey> deriveKey(String password, List<int> salt) {
    return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// 加密。返回自描述容器字节流（见类注释 ②）。
  ///
  /// [salt] 只应在测试里指定（让用例结果可复现）；生产一律随机。
  Future<Uint8List> seal(
    List<int> clearText,
    String password, {
    List<int>? salt,
  }) async {
    final usedSalt = salt ?? newSalt();
    if (usedSalt.length != saltLength) {
      throw ArgumentError.value(
          usedSalt.length, 'salt', '盐必须是 $saltLength 字节');
    }
    final key = await deriveKey(password, usedSalt);
    // nonce 交给算法自己生成：GCM 下"同一密钥 + 同一 nonce"是灾难性的
    // （两条密文异或即等于明文异或），自己指定 IV 没有任何好处。
    final box = await _algorithm.encrypt(clearText, secretKey: key);
    return _encode(usedSalt, box);
  }

  /// 解密。失败一律抛 [SecurityException]：
  /// 容器不对 → [SecurityErrorKind.notEncrypted]；认证不过 → authenticationFailed。
  Future<Uint8List> open(List<int> blob, String password) async {
    final parsed = _decode(blob);
    final key = await deriveKey(password, parsed.salt);
    try {
      final clearText = await _algorithm.decrypt(parsed.box, secretKey: key);
      return Uint8List.fromList(clearText);
    } on SecretBoxAuthenticationError catch (error) {
      throw SecurityException(
        'AEAD 认证失败：密码错误或数据被改动',
        kind: SecurityErrorKind.authenticationFailed,
        cause: error,
      );
    }
  }

  /// 只看字节流是不是素页加密容器（不解密、不需要密码）。
  /// UI 用它决定恢复时该不该先弹密码框——让用户输入密码再去告诉他"这文件
  /// 根本没加密"，是纯浪费一次输入。
  bool looksEncrypted(List<int> blob) {
    if (blob.length < headerLength) return false;
    for (var i = 0; i < magic.length; i++) {
      if (blob[i] != magic[i]) return false;
    }
    return true;
  }

  Uint8List _encode(List<int> salt, SecretBox box) {
    final builder = BytesBuilder(copy: false)
      ..add(magic)
      ..add(<int>[salt.length, box.nonce.length, box.mac.bytes.length])
      ..add(salt)
      // cryptography 的 SecretBox 三件套：nonce + cipherText + mac。
      // 注意 **mac 不在 cipherText 尾部**（这是 AEAD 的常见误解），
      // 拼回去时必须显式带上，否则解出来的数据是"能通过但没被认证"的。
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return builder.takeBytes();
  }

  _ParsedBlob _decode(List<int> blob) {
    if (!looksEncrypted(blob)) {
      throw const SecurityException(
        '缺少素页加密容器文件头',
        kind: SecurityErrorKind.notEncrypted,
      );
    }
    final saltLen = blob[6];
    final nonceLen = blob[7];
    final macLen = blob[8];
    final headEnd = headerLength + saltLen + nonceLen + macLen;
    if (blob.length < headEnd) {
      throw const SecurityException(
        '加密容器长度不足（文件可能被截断）',
        kind: SecurityErrorKind.notEncrypted,
      );
    }
    // 转一次而不是每切片都拷一份：备份包动辄几十 MB，多拷两遍就是多占两份内存
    final bytes = blob is Uint8List ? blob : Uint8List.fromList(blob);
    final macStart = bytes.length - macLen;
    final saltStart = headerLength;
    final nonceStart = saltStart + saltLen;
    final cipherStart = nonceStart + nonceLen;
    return _ParsedBlob(
      salt: Uint8List.sublistView(bytes, saltStart, nonceStart),
      box: SecretBox(
        Uint8List.sublistView(bytes, cipherStart, macStart),
        nonce: Uint8List.sublistView(bytes, nonceStart, cipherStart),
        mac: Mac(Uint8List.sublistView(bytes, macStart)),
      ),
    );
  }
}

/// [_decode] 的产物：盐与 SecretBox 分开拿，方便 open 之外的地方复用解析结果
class _ParsedBlob {
  const _ParsedBlob({required this.salt, required this.box});

  final Uint8List salt;
  final SecretBox box;
}
