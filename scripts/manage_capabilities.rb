# Bundle ID 能力开关（推送、内购、Sign in with Apple 等）
#
# 环境变量：
#   BUNDLE_IDENTIFIER   com.demo.app
#   CAPABILITY_ACTION   list | enable | disable
#   CAPABILITIES        能力类型，逗号分隔，例如 PUSH_NOTIFICATIONS,IN_APP_PURCHASE
require_relative "common"

run_task do
  identifier = env("BUNDLE_IDENTIFIER")
  action     = env("CAPABILITY_ACTION", default: "list")
  types      = env("CAPABILITIES", required: false, default: "")
               .split(",").map { |t| t.strip.upcase }.reject(&:empty?)

  login!

  bundle_id = Spaceship::ConnectAPI::BundleId.find(identifier)
  raise "Bundle ID #{identifier} 不存在，请先创建" unless bundle_id
  puts "[能力] Bundle ID #{identifier}（#{bundle_id.id}）"

  if action != "list" && types.empty?
    raise "#{action} 操作需要指定至少一个能力类型"
  end

  results = types.map do |type|
    begin
      case action
      when "enable"
        bundle_id.create_capability(type)
        puts "[能力] 已开启 #{type}"
        { "type" => type, "ok" => true, "enabled" => true }
      when "disable"
        bundle_id.update_capability(type, enabled: false)
        puts "[能力] 已关闭 #{type}"
        { "type" => type, "ok" => true, "enabled" => false }
      else
        nil
      end
    rescue StandardError => e
      # 有些能力需要额外配置（如 App Groups / iCloud 容器），单个失败不中断其余
      warn "[能力] #{type} 操作失败：#{e.message}"
      { "type" => type, "ok" => false, "error" => e.message }
    end
  end.compact

  current = bundle_id.get_capabilities.map do |c|
    { "id" => c.id, "type" => (c.capability_type rescue nil), "settings" => (c.settings rescue nil) }
  end
  puts "[能力] 当前已开启 #{current.size} 项：#{current.map { |c| c['type'] }.compact.join(', ')}"

  failed = results.count { |r| !r["ok"] }
  write_result(
    "ok" => failed.zero?,
    "action" => "manage_capabilities",
    "capability_action" => action,
    "error" => failed.zero? ? nil : "#{failed} 项能力操作失败，详见 results",
    "bundle_identifier" => identifier,
    "results" => results,
    "capabilities" => current
  )
  exit 1 unless failed.zero?
end
