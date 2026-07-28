# 在 App Store Connect 创建 App 记录
#
# 走的是 Spaceship::ConnectAPI::App.create（fastlane produce 用的同一条路径）。
# 带 API Key 时 spaceship 会打官方主机 api.appstoreconnect.apple.com，
# 用 Apple ID 会话时打内部主机 appstoreconnect.apple.com/iris。
# fastlane 官方支持表里 produce 对 API Key 标注 No，所以 p8 能不能建 App
# 需要实测；失败会在日志里给出替代方案，不会静默。
#
# 环境变量：
#   BUNDLE_IDENTIFIER  com.demo.app（必须已在开发者门户注册）
#   APP_NAME           App 名称，App Store 上全局唯一
#   PRIMARY_LANGUAGE   zh-Hans | en-US | en-GB | en-AU
#   SKU                内部编号，留空则用 Bundle ID
#   COMPANY_NAME       首次建 App 的账号需要填
#   APP_VERSION        初始版本号，默认 1.0
require_relative "common"

LANGUAGES = {
  "zh-Hans" => "简体中文",
  "en-US"   => "英语（美国）",
  "en-GB"   => "英语（英国）",
  "en-AU"   => "英语（澳大利亚）"
}.freeze

run_task do
  identifier = env("BUNDLE_IDENTIFIER")
  app_name   = env("APP_NAME")
  locale     = env("PRIMARY_LANGUAGE", default: "zh-Hans")
  sku        = env("SKU", required: false, default: identifier)
  company    = env("COMPANY_NAME", required: false)
  version    = env("APP_VERSION", default: "1.0")

  unless LANGUAGES.key?(locale)
    raise "不支持的语言 #{locale}，可选：#{LANGUAGES.keys.join(', ')}"
  end

  using_api_key = !ENV["ASC_KEY_ID"].to_s.strip.empty?
  login_tunes!

  # 已存在就复用，避免重复创建报错
  existing = Spaceship::ConnectAPI::App.find(identifier)
  if existing
    puts "[App] 已存在，直接复用：#{existing.name}（id=#{existing.id}）"
    write_result(
      "ok" => true, "action" => "create_app", "created" => false,
      "app" => { "id" => existing.id, "name" => existing.name,
                 "bundle_id" => existing.bundle_id, "sku" => existing.sku }
    )
    next
  end

  puts "[App] 创建 #{app_name}"
  puts "[App]   Bundle ID = #{identifier}"
  puts "[App]   主语言    = #{LANGUAGES[locale]}（#{locale}）"
  puts "[App]   SKU       = #{sku}"
  puts "[App]   初始版本  = #{version}"

  begin
    app = Spaceship::ConnectAPI::App.create(
      name: app_name,
      version_string: version,
      sku: sku.to_s,
      primary_locale: locale,
      bundle_id: identifier,
      platforms: ["IOS"],
      company_name: company
    )
  rescue StandardError => e
    if using_api_key
      warn ""
      warn "[排查] 用 API Key 建 App 失败了。Apple 官方 API 未公开文档化建 App 端点，"
      warn "       fastlane 的支持表里 produce 对 API Key 也标注为 No，因此这一步可能确实不被支持。"
      warn "       替代方案（任选其一，都只需做一次）："
      warn "       1. 直接去 App Store Connect 网页手动建 App，最快"
      warn "       2. 把凭据切到 Apple ID 模式并提供 FASTLANE_SESSION 再跑本任务"
      warn "       其余任务（证书 / Bundle ID / Profile / 设备 / 能力 / 元数据）不受影响。"
      warn ""
    end
    raise e
  end

  puts "[App] 创建成功 id=#{app.id}"

  write_result(
    "ok" => true, "action" => "create_app", "created" => true,
    "app" => { "id" => app.id, "name" => app.name, "bundle_id" => app.bundle_id,
               "sku" => sku, "locale" => locale, "primary_language" => LANGUAGES[locale] }
  )
end
