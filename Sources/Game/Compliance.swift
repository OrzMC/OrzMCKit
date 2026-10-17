// 本文件由 scripts/sync_compliance.py 生成；请改父仓库 docs/compliance/compliance.json 后重新生成。
import Foundation

/// Minecraft Usage Guidelines 要求的声明与联系方式（单一事实源）。
public enum Compliance {
    public static let disclaimer = "NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT."
    public static let disclaimerZh = "OrzMC 是独立的社区开源项目，与 Mojang / Microsoft 无隶属、赞助或背书关系，对本项目负责。"
    public static let trademarkZh = "“Minecraft”名称、品牌与素材的一切权利归 Mojang / Microsoft 所有。"
    public static let contactURL = "https://github.com/OrzMC"
    public static let privacyURL = "https://orzmc.jokerhub.cn/privacy/"
    public static let website = "https://orzmc.jokerhub.cn"

    /// 免责声明文本（英文 / 中文 / 商标各占一行；CLI 页脚与 `--json` 同源）。
    public static var text: String {
        [disclaimer, disclaimerZh, trademarkZh].joined(separator: "\n")
    }
}
