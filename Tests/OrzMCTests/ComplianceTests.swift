import Foundation
import Game
import Testing

/// `Compliance.text` 是 CLI `--version` / `--json` 的声明来源：中英各占一行、无邮箱。
///
/// 文本本身由父仓库 `docs/compliance/compliance.json` + `scripts/sync_compliance.py`
/// 生成（单一事实源）；这里只守住**渲染约定**，防止回退成「中英同一行 + 联系邮箱」。
@Test func complianceTextIsMultiLineAndEmailFree() {
    let text = Compliance.text
    #expect(text.split(separator: "\n").count == 3)
    #expect(text.contains(Compliance.disclaimer))
    #expect(text.contains(Compliance.disclaimerZh))
    #expect(text.contains(Compliance.trademarkZh))
    #expect(!text.contains("@"))
}
