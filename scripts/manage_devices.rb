# 设备管理：注册 / 启用 / 停用 / 重命名
# AdHoc 和 Development 类型的 Profile 必须有已注册设备才能创建
#
# 环境变量：
#   DEVICE_ACTION   register | enable | disable | rename
#   DEVICE_UDIDS    UDID，多个用逗号或换行分隔
#   DEVICE_NAMES    名称，与 UDID 一一对应；少于 UDID 数量时自动补 Device N
#   DEVICE_PLATFORM IOS | MAC_OS
require_relative "common"

run_task do
  action   = env("DEVICE_ACTION", default: "register")
  udids    = env("DEVICE_UDIDS").split(/[,\n]/).map(&:strip).reject(&:empty?)
  names    = env("DEVICE_NAMES", required: false, default: "").split(/[,\n]/).map(&:strip)
  platform = env("DEVICE_PLATFORM", default: "IOS")

  raise "没有提供任何 UDID" if udids.empty?

  login!

  results = udids.each_with_index.map do |udid, i|
    name = names[i].to_s.empty? ? "Device #{i + 1}" : names[i]
    begin
      case action
      when "register"
        # find_or_create 避免重复注册报错（Apple 对已注册的 UDID 会返回 409）
        device = Spaceship::ConnectAPI::Device.find_or_create(udid, name: name, platform: platform)
        puts "[设备] 注册/复用 #{udid} → #{device.name}（#{device.status}）"
        { "udid" => udid, "ok" => true, "id" => device.id, "name" => device.name, "status" => device.status }
      when "enable"
        device = Spaceship::ConnectAPI::Device.enable(udid)
        puts "[设备] 已启用 #{udid}"
        { "udid" => udid, "ok" => true, "status" => device.status }
      when "disable"
        device = Spaceship::ConnectAPI::Device.disable(udid)
        puts "[设备] 已停用 #{udid}"
        { "udid" => udid, "ok" => true, "status" => device.status }
      when "rename"
        device = Spaceship::ConnectAPI::Device.rename(udid, name)
        puts "[设备] 已重命名 #{udid} → #{name}"
        { "udid" => udid, "ok" => true, "name" => device.name }
      else
        raise "未知操作 #{action}，可选：register / enable / disable / rename"
      end
    rescue StandardError => e
      # 单台失败不影响其余设备
      warn "[设备] #{udid} 失败：#{e.message}"
      { "udid" => udid, "ok" => false, "error" => e.message }
    end
  end

  failed = results.count { |r| !r["ok"] }
  devices = Spaceship::ConnectAPI::Device.all.map do |d|
    { "id" => d.id, "name" => d.name, "udid" => d.udid, "platform" => d.platform, "status" => d.status }
  end
  puts "[设备] 完成：成功 #{results.size - failed} / 失败 #{failed}，账号下共 #{devices.size} 台"

  write_result(
    "ok" => failed.zero?,
    "action" => "manage_devices",
    "device_action" => action,
    "error" => failed.zero? ? nil : "#{failed} 台设备操作失败，详见 results",
    "results" => results,
    "devices" => devices
  )
  exit 1 unless failed.zero?
end
