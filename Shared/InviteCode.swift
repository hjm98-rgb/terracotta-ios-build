import Foundation

/// 陶瓦邀请码编解码，算法与 PC / 安卓端（Rust 的 `create_room` / `parse`）逐位对齐。
///
/// 格式：`U/XXXX-XXXX-XXXX-XXXX`（21 字符）
/// 字符表：`0123456789ABCDEFGHJKLMNPQRSTUVWXYZ`（34 个，去掉了容易看错的 I 和 O；输入时 I→1、O→0）
/// 校验：数值必须能被 **7** 整除
/// 前 8 位 → `network_name  = scaffolding-mc-XXXX-XXXX`
/// 后 8 位 → `network_secret = XXXX-XXXX`
///
/// 注意：34^16 ≈ 5.08e24，远超 UInt64 上限，所以这里**不做大数运算**，
/// 直接保存 16 位 34 进制数字（digits[0] 为最低位，与 Rust 端 push 顺序一致），
/// 判定 7 的整除性用逐位取余完成。
struct InviteCode: Equatable, Hashable {
    /// 16 个 34 进制位，digits[0] 是最低位。
    let digits: [UInt8]

    static let charset: [Character] = Array("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let base: UInt8 = 34
    static let digitCount = 16
    static let codeLength = 21

    // MARK: - 派生字段

    var code: String {
        var characters: [Character] = ["U", "/"]
        for i in 0..<Self.digitCount {
            if i == 4 || i == 8 || i == 12 { characters.append("-") }
            characters.append(Self.charset[Int(digits[i])])
        }
        return String(characters)
    }

    var networkName: String {
        var characters: [Character] = []
        for i in 0..<8 {
            if i == 4 { characters.append("-") }
            characters.append(Self.charset[Int(digits[i])])
        }
        return "scaffolding-mc-" + String(characters)
    }

    var networkSecret: String {
        var characters: [Character] = []
        for i in 8..<16 {
            if i == 12 { characters.append("-") }
            characters.append(Self.charset[Int(digits[i])])
        }
        return String(characters)
    }

    // MARK: - 生成

    /// 随机生成房间码（对应 Rust 的 `create_room`：随机值再使其被 7 整除）。
    static func random() -> InviteCode {
        var digits: [UInt8] = (0..<digitCount).map { _ in UInt8.random(in: 0...33) }
        if digits[digitCount - 1] == 0 { digits[digitCount - 1] = 1 }

        let remainder = mod7(digits)
        if remainder != 0 {
            digits = subtracting(remainder, from: digits)
        }
        return InviteCode(digits: digits)
    }

    // MARK: - 解析

    /// 从任意文本里解析邀请码（用户粘贴时常常带空格、表情、"U/" 前后废话）。
    static func parse(_ raw: String) -> InviteCode? {
        let characters = Array(raw.uppercased())
        guard characters.count >= codeLength else { return nil }

        for start in 0...(characters.count - codeLength) {
            guard characters[start] == "U", characters[start + 1] == "/" else { continue }

            let segment = Array(characters[(start + 2)..<(start + codeLength)])
            guard segment.count == 19 else { continue }

            var digits: [UInt8] = []
            digits.reserveCapacity(digitCount)
            var valid = true

            // Rust 端是从高位往低位解析后反转的，这里按字符直读再按位重排
            for (index, character) in segment.enumerated() {
                if index == 4 || index == 9 || index == 14 {
                    if character != "-" { valid = false; break }
                    continue
                }
                guard let digit = lookup(character) else { valid = false; break }
                digits.append(digit)
            }

            guard valid, digits.count == digitCount else { continue }
            // 邀请码字符串的最左位就是 digits[0]（最低位），与 Rust 端 push 顺序一致，无需翻转
            guard mod7(digits) == 0 else { continue }

            return InviteCode(digits: digits)
        }

        return nil
    }

    // MARK: - 内部

    private static func lookup(_ character: Character) -> UInt8? {
        let normalized: Character
        switch character {
        case "I": normalized = "1"
        case "O": normalized = "0"
        default: normalized = character
        }
        guard let index = charset.firstIndex(of: normalized) else { return nil }
        return UInt8(index)
    }

    /// 计算 34 进制数对 7 的余数：Horner 法必须从**最高位**开始，所以对 LSD-first 数组反向遍历。
    private static func mod7(_ digits: [UInt8]) -> UInt8 {
        digits.reversed().reduce(UInt8(0)) { ($0 * base + $1) % 7 }
    }

    /// 从 34 进制数字里减去一个小值（带借位），用于把随机值调成 7 的倍数。
    private static func subtracting(_ amount: UInt8, from digits: [UInt8]) -> [UInt8] {
        var result = digits
        var borrow = Int(amount)

        for i in 0..<result.count where borrow > 0 {
            let value = Int(result[i]) - borrow
            if value < 0 {
                result[i] = UInt8(value + Int(base))
                borrow = 1
            } else {
                result[i] = UInt8(value)
                borrow = 0
            }
        }
        return result
    }
}
