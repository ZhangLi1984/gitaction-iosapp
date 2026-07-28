# 清理：吊销证书 / 删除描述文件
#
# Distribution 证书上限只有 2~3 张，满了之后创建证书会直接失败，
# 这个任务用来腾位置。
#
# ⚠️ 吊销证书后，所有用它签名的 Profile 立即失效，已上架 App 不受影响但无法再签新包。
#
# 注意：Bundle ID 无法通过 App Store Connect API 删除（spaceship 没有对应方法），
#      需要去开发者门户网页手动删。
#
# 环境变量：
#   CLEANUP_TARGET  certificate | profile
#   CLEANUP_IDS     资源 ID，逗号分隔
require_relative "common"

run_task do
  target = env("CLEANUP_TARGET")
  ids    = env("CLEANUP_IDS").split(",").map(&:strip).reject(&:empty?)
  raise "没有提供要删除的 ID" if ids.empty?

  login!

  items =
    case target
    when "certificate" then Spaceship::ConnectAPI::Certificate.all
    when "profile"     then Spaceship::ConnectAPI::Profile.all
    else raise "未知的清理对象 #{target}，可选：certificate / profile"
    end

  missing = ids - items.map(&:id)
  raise "以下 ID 不存在：#{missing.join(', ')}" unless missing.empty?

  results = ids.map do |id|
    item = items.find { |x| x.id == id }
    label = "#{item.name}（#{id}）"
    begin
      item.delete!
      puts "[清理] 已#{target == 'certificate' ? '吊销' : '删除'} #{label}"
      { "id" => id, "name" => item.name, "ok" => true }
    rescue StandardError => e
      warn "[清理] #{label} 失败：#{e.message}"
      { "id" => id, "name" => item.name, "ok" => false, "error" => e.message }
    end
  end

  failed = results.count { |r| !r["ok"] }
  remaining =
    case target
    when "certificate"
      Spaceship::ConnectAPI::Certificate.all.map { |c| certificate_summary(c) }
    else
      Spaceship::ConnectAPI::Profile.all.map { |p| { "id" => p.id, "name" => p.name, "type" => p.profile_type } }
    end
  puts "[清理] 完成，剩余 #{remaining.size} 个"

  write_result(
    "ok" => failed.zero?,
    "action" => "cleanup_resources",
    "target" => target,
    "error" => failed.zero? ? nil : "#{failed} 项删除失败，详见 results",
    "results" => results,
    "remaining" => remaining
  )
  exit 1 unless failed.zero?
end
