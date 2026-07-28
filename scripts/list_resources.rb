# 拉取账号下的全部资源，供网页刷新下拉框用
require_relative "common"

run_task do
  login!

  certificates = Spaceship::ConnectAPI::Certificate.all.map { |c| certificate_summary(c) }
  puts "[资源] 证书 #{certificates.size} 张"

  bundle_ids = Spaceship::ConnectAPI::BundleId.all.map do |b|
    { "id" => b.id, "identifier" => b.identifier, "name" => b.name, "platform" => b.platform }
  end
  puts "[资源] Bundle ID #{bundle_ids.size} 个"

  profiles = Spaceship::ConnectAPI::Profile.all(includes: "bundleId").map do |p|
    {
      "id" => p.id,
      "name" => p.name,
      "uuid" => p.uuid,
      "type" => p.profile_type,
      "state" => p.profile_state,
      "expires_at" => p.expiration_date,
      "bundle_identifier" => (p.bundle_id&.identifier rescue nil)
    }
  end
  puts "[资源] Profile #{profiles.size} 个"

  devices = Spaceship::ConnectAPI::Device.all.map do |d|
    { "id" => d.id, "name" => d.name, "udid" => d.udid, "platform" => d.platform, "status" => d.status }
  end
  puts "[资源] 设备 #{devices.size} 台"

  write_result(
    "ok" => true,
    "action" => "list_resources",
    "certificates" => certificates,
    "bundle_ids" => bundle_ids,
    "profiles" => profiles,
    "devices" => devices
  )
end
