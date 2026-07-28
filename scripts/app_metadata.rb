# App 多语言元数据：读取 / 更新
#
# 字段分布在两个对象里（Apple 的设计）：
#   AppInfoLocalization         → 名称、副标题、隐私政策 URL       跨版本，改了立刻影响
#   AppStoreVersionLocalization → 描述、关键词、新增内容、推广文本、营销/支持 URL  属于当前编辑版本
#
# 环境变量：
#   BUNDLE_IDENTIFIER  com.demo.app
#   METADATA_ACTION    read | update
#   METADATA_LOCALE    zh-Hans | en-US | en-GB | en-AU
#   METADATA_JSON      要更新的字段，例如
#                      {"name":"新名字","subtitle":"副标题","description":"...","keywords":"a,b,c"}
#                      未出现的字段一律不动
#                      （workflow_dispatch 最多 10 个输入，所以打包成一个 JSON）
require_relative "common"

# JSON 里的键 → 模型属性
INFO_FIELDS = {
  "name"        => :name,
  "subtitle"    => :subtitle,
  "privacy_url" => :privacy_policy_url
}.freeze

VERSION_FIELDS = {
  "description"      => :description,
  "keywords"         => :keywords,
  "whats_new"        => :whats_new,
  "promotional_text" => :promotional_text,
  "marketing_url"    => :marketing_url,
  "support_url"      => :support_url
}.freeze

def dump_localization(loc, fields)
  fields.values.each_with_object("locale" => loc.locale) do |attr, h|
    h[attr.to_s] = (loc.public_send(attr) rescue nil)
  end
end

def collect(payload, fields)
  fields.each_with_object({}) do |(key, attr), h|
    value = payload[key]
    h[attr] = value unless value.to_s.strip.empty?
  end
end

run_task do
  identifier = env("BUNDLE_IDENTIFIER")
  action     = env("METADATA_ACTION", default: "read")
  locale     = env("METADATA_LOCALE", default: "zh-Hans")

  login_tunes!
  app = find_app!(identifier)
  puts "[元数据] App：#{app.name}（id=#{app.id}）"

  app_info  = app.fetch_edit_app_info
  info_locs = app_info ? app_info.get_app_info_localizations : []
  version   = app.get_edit_app_store_version
  ver_locs  = version ? version.get_app_store_version_localizations : []

  puts "[元数据] 可编辑版本：#{version ? version.version_string : '无（App 没有处于可编辑状态的版本）'}"
  puts "[元数据] 名称类语言：#{info_locs.map(&:locale).join(', ')}"
  puts "[元数据] 描述类语言：#{ver_locs.map(&:locale).join(', ')}"

  if action == "read"
    write_result(
      "ok" => true, "action" => "app_metadata", "metadata_action" => "read",
      "app" => { "id" => app.id, "name" => app.name, "bundle_id" => app.bundle_id },
      "version" => version && { "id" => version.id, "version_string" => version.version_string,
                                "state" => (version.app_store_state rescue nil) },
      "app_info_localizations" => info_locs.map { |l| dump_localization(l, INFO_FIELDS) },
      "version_localizations"  => ver_locs.map { |l| dump_localization(l, VERSION_FIELDS) }
    )
    next
  end

  payload =
    begin
      JSON.parse(env("METADATA_JSON", default: "{}"))
    rescue JSON::ParserError => e
      raise "METADATA_JSON 不是合法 JSON：#{e.message}"
    end
  unknown = payload.keys - INFO_FIELDS.keys - VERSION_FIELDS.keys
  warn "[元数据] 忽略未知字段：#{unknown.join(', ')}" unless unknown.empty?

  info_updates = collect(payload, INFO_FIELDS)
  ver_updates  = collect(payload, VERSION_FIELDS)
  raise "没有提供任何要更新的字段" if info_updates.empty? && ver_updates.empty?

  updated = {}

  unless info_updates.empty?
    loc = info_locs.find { |l| l.locale == locale }
    raise "该 App 的名称类元数据没有 #{locale} 语言（现有：#{info_locs.map(&:locale).join(', ')}）。" \
          "请先在 App Store Connect 网页上为这个语言添加本地化。" unless loc
    loc.update(attributes: info_updates)
    puts "[元数据] 已更新名称类字段（#{locale}）：#{info_updates.keys.join(', ')}"
    updated["app_info"] = info_updates.keys.map(&:to_s)
  end

  unless ver_updates.empty?
    raise "App 没有处于可编辑状态的版本，无法修改描述类字段" unless version
    loc = ver_locs.find { |l| l.locale == locale }
    raise "该版本没有 #{locale} 语言（现有：#{ver_locs.map(&:locale).join(', ')}）。" \
          "请先在 App Store Connect 网页上为这个语言添加本地化。" unless loc
    loc.update(attributes: ver_updates)
    puts "[元数据] 已更新描述类字段（#{locale}）：#{ver_updates.keys.join(', ')}"
    updated["version"] = ver_updates.keys.map(&:to_s)
  end

  write_result(
    "ok" => true, "action" => "app_metadata", "metadata_action" => "update",
    "locale" => locale,
    "app" => { "id" => app.id, "name" => app.name, "bundle_id" => app.bundle_id },
    "updated" => updated
  )
end
