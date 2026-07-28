# 拉取账号下的全部资源，供网页刷新下拉框用
require_relative "common"

run_task do
  # tunes 一起登上，这样能顺带把 App 列表也拉回来
  login!(portal: true, tunes: true)

  raw_certs = Spaceship::ConnectAPI::Certificate.all
  certificates = raw_certs.map { |c| certificate_summary(c) }
  puts "[资源] 证书 #{certificates.size} 张"

  raw_bundle_ids = Spaceship::ConnectAPI::BundleId.all
  bundle_ids = raw_bundle_ids.map do |b|
    { "id" => b.id, "identifier" => b.identifier, "name" => b.name, "platform" => b.platform }
  end
  puts "[资源] Bundle ID #{bundle_ids.size} 个"

  raw_profiles = Spaceship::ConnectAPI::Profile.all(includes: "bundleId")
  profiles = raw_profiles.map do |p|
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

  # App 列表拉不到不算致命（可能只有门户权限），降级成空列表
  apps =
    begin
      Spaceship::ConnectAPI::App.all.map do |a|
        { "id" => a.id, "name" => a.name, "bundle_id" => a.bundle_id,
          "sku" => a.sku, "primary_locale" => a.primary_locale }
      end
    rescue StandardError => e
      warn "[资源] App 列表获取失败（不影响其它资源）：#{e.message}"
      []
    end
  puts "[资源] App #{apps.size} 个"

  team_id, source = detect_team_id(
    certificates: raw_certs, bundle_ids: raw_bundle_ids, profiles: raw_profiles
  )
  if team_id
    puts "[资源] Team ID = #{team_id}（来自#{source}）"
  else
    puts "[资源] Team ID 无法推断：账号下还没有任何证书 / Bundle ID / 描述文件"
  end

  write_result(
    "ok" => true,
    "action" => "list_resources",
    "team_id" => team_id,
    "team_id_source" => source,
    "apps" => apps,
    "certificates" => certificates,
    "bundle_ids" => bundle_ids,
    "profiles" => profiles,
    "devices" => devices
  )
end
