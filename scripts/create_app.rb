# 在 App Store Connect 创建 App 记录
#
# ⚠️ 这个操作走的是旧的 iTunes Connect 接口，Apple 至今未开放 App Store Connect API
#    的建 App 端点（fastlane 官方支持表里 produce 对 API Key 明确是 No）。
#    因此本任务只能用 Apple ID + FASTLANE_SESSION，不能用 API Key。
#
# 环境变量：
#   BUNDLE_IDENTIFIER  com.demo.app（必须已在开发者门户注册）
#   APP_NAME           App 名称，App Store 上全局唯一
#   PRIMARY_LANGUAGE   zh-Hans | en-US | en-GB | en-AU
#   SKU                内部编号，留空则用 Bundle ID
#   COMPANY_NAME       首次建 App 的账号需要填
require_relative "common"

# locale → spaceship 需要的 iTunes Connect 语言名
# 取值来自 fastlane 的 languageMapping.json
LANGUAGES = {
  "zh-Hans" => { itc: "Simplified Chinese",  label: "简体中文" },
  "en-US"   => { itc: "English",             label: "英语（美国）" },
  "en-GB"   => { itc: "UK English",          label: "英语（英国）" },
  "en-AU"   => { itc: "Australian English",  label: "英语（澳大利亚）" }
}.freeze

run_task do
  identifier = env("BUNDLE_IDENTIFIER")
  app_name   = env("APP_NAME")
  locale     = env("PRIMARY_LANGUAGE", default: "zh-Hans")
  sku        = env("SKU", required: false, default: identifier)
  company    = env("COMPANY_NAME", required: false)

  lang = LANGUAGES[locale]
  raise "不支持的语言 #{locale}，可选：#{LANGUAGES.keys.join(', ')}" unless lang

  login_tunes!

  # 同名或同 Bundle ID 的 App 已存在就直接复用，避免重复创建报错
  existing = Spaceship::Tunes::Application.find(identifier)
  if existing
    puts "[App] 已存在，直接复用：#{existing.name}（Apple ID #{existing.apple_id}）"
    write_result(
      "ok" => true,
      "action" => "create_app",
      "created" => false,
      "app" => {
        "apple_id" => existing.apple_id,
        "name" => existing.name,
        "bundle_id" => existing.bundle_id,
        "sku" => (existing.vendor_id rescue nil)
      }
    )
    next
  end

  puts "[App] 创建 #{app_name}"
  puts "[App]   Bundle ID = #{identifier}"
  puts "[App]   主语言    = #{lang[:label]}（#{lang[:itc]} / #{locale}）"
  puts "[App]   SKU       = #{sku}"

  app = Spaceship::Tunes::Application.create!(
    name: app_name,
    primary_language: lang[:itc],
    sku: sku.to_s,
    bundle_id: identifier,
    company_name: company,
    platform: "ios"
  )

  puts "[App] 创建成功，Apple ID = #{app.apple_id}"

  write_result(
    "ok" => true,
    "action" => "create_app",
    "created" => true,
    "app" => {
      "apple_id" => app.apple_id,
      "name" => app.name,
      "bundle_id" => app.bundle_id,
      "sku" => sku,
      "primary_language" => lang[:label],
      "locale" => locale
    }
  )
end
