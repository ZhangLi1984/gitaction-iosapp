# 创建 Bundle ID（App Identifier）
#
# 环境变量：
#   BUNDLE_IDENTIFIER  com.demo.app
#   BUNDLE_NAME        显示名称（Apple 只允许字母数字和空格）
#   BUNDLE_PLATFORM    IOS | MAC_OS | UNIVERSAL
require_relative "common"

run_task do
  identifier = env("BUNDLE_IDENTIFIER")
  name       = env("BUNDLE_NAME")
  platform   = env("BUNDLE_PLATFORM", default: "IOS")

  # Apple 拒绝含特殊字符的 name，先清洗，避免报一个很难懂的 400
  sanitized = name.gsub(/[^A-Za-z0-9 ]/, " ").squeeze(" ").strip
  if sanitized != name
    puts "[BundleID] 名称含非法字符，已清洗: #{name.inspect} -> #{sanitized.inspect}"
  end
  abort("[错误] 名称清洗后为空，请使用字母数字") if sanitized.empty?

  login!

  found = Spaceship::ConnectAPI::BundleId.all(filter: { identifier: identifier })
                                         .find { |b| b.identifier == identifier }

  if found
    puts "[BundleID] 已存在，直接复用 id=#{found.id}"
    bundle_id = found
    created = false
  else
    puts "[BundleID] 创建 #{identifier} (#{platform}) ..."
    bundle_id = Spaceship::ConnectAPI::BundleId.create(
      name: sanitized,
      identifier: identifier,
      platform: platform
    )
    created = true
    puts "[BundleID] 创建成功 id=#{bundle_id.id}"
  end

  write_result(
    "ok" => true,
    "action" => "create_bundle_id",
    "created" => created,
    "bundle_id" => {
      "id" => bundle_id.id,
      "identifier" => bundle_id.identifier,
      "name" => bundle_id.name,
      "platform" => bundle_id.platform
    }
  )
end
