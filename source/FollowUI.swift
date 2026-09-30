import AppKit
import SwiftUI

enum FollowLinks {
    static let xiaohongshu = URL(string: "https://xhslink.cn/o/9uYJj82pMFu")!
    static let website = URL(string: "https://www.jiabinlu.com/products/fix-clipboard/#follow")!
}

struct FollowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text("工具免费，关注随意。 ").font(.system(size: 23, weight: .bold))
                    Text("Fix Clipboard 的全部功能都已免费开放。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Text("我是 Louis。这个工具从一次复制粘贴故障开始，也因为小红书上大家的反馈继续改进。")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Text("如果它帮到了你，欢迎关注我。接下来继续分享实用技术、AI 做产品的过程，以及把重复工作自动化的经验。")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Button("去小红书原帖 · 点击作者头像关注") { NSWorkspace.shared.open(FollowLinks.xiaohongshu) }
                .controlSize(.large)
            Divider()
            HStack(spacing: 20) {
                if let url = Bundle.main.url(forResource: "WeChatOfficial", withExtension: "jpg"), let qr = NSImage(contentsOf: url) {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(nsImage: qr).resizable().interpolation(.none).scaledToFit().frame(width: 160, height: 160)
                    }.buttonStyle(.plain).help("打开公众号二维码原图")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("微信扫码关注公众号").font(.headline)
                    Text("阅读更完整的 AI、产品与工作方法分享。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("在网页查看关注入口") { NSWorkspace.shared.open(FollowLinks.website) }
                }
            }
            Text("无需付费、注册或输入授权码。不会检查你是否关注，也不会为关注发送通知或上传使用记录。关闭此窗口即可继续使用。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 510).background(Color(nsColor: .windowBackgroundColor))
    }
}
