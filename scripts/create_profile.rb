# 创建 Provisioning Profile
#
# 证书选择逻辑：
#   传了 CERTIFICATE_IDS -> 用指定的
#   没传：可用证书 0 张 -> 报错
#         可用证书 1 张 -> 自动使用
#         可用证书 >1 张 -> 报错并返回候选列表，让网页去选
#
# 环境变量：
#   BUNDLE_IDENTIFIER  com.demo.app
#   PROFILE_NAME       Profile 名称
#   PROFILE_TYPE       IOS_APP_STORE | IOS_APP_ADHOC | IOS_APP_DEVELOPMENT | IOS_APP_INHOUSE ...
#   CERTIFICATE_IDS    逗号分隔，可选
#   REPLACE_EXISTING   true/false，同名 profile 是否先删除重建
require_relative "common"

run_task do
  identifier   = env("BUNDLE_IDENTIFIER")
  profile_name = env("PROFILE_NAME")
  profile_type = env("PROFILE_TYPE", default: "IOS_APP_STORE")
  cert_ids_in  = env("CERTIFICATE_IDS", required: false, default: "").split(",").map(&:strip).reject(&:empty?)
  replace      = env("REPLACE_EXISTING", required: false, default: "true") == "true"

  login!

  # ---- 1. Bundle ID ----
  bundle_id = Spaceship::ConnectAPI::BundleId.all(filter: { identifier: identifier })
                                             .find { |b| b.identifier == identifier }
  unless bundle_id
    raise "Bundle ID #{identifier} 不存在，请先创建 Bundle ID"
  end
  puts "[Profile] Bundle ID: #{bundle_id.identifier} (#{bundle_id.id})"

  # ---- 2. 选证书 ----
  allowed_types = cert_types_for_profile(profile_type)
  all_certs = Spaceship::ConnectAPI::Certificate.all
  usable = all_certs.select { |c| allowed_types.include?(c.certificate_type) }
  puts "[Profile] #{profile_type} 可用证书 #{usable.size} 张"

  certificates =
    if cert_ids_in.any?
      picked = usable.select { |c| cert_ids_in.include?(c.id) }
      missing = cert_ids_in - picked.map(&:id)
      raise "指定的证书 ID 不存在或类型不匹配: #{missing.join(', ')}" if missing.any?
      picked
    elsif usable.empty?
      raise "没有可用的 #{allowed_types.join('/')} 证书，请先创建证书"
    elsif usable.size == 1
      puts "[Profile] 只有 1 张证书，自动选择: #{usable.first.name}"
      usable
    else
      # 多张证书 -> 交给网页去选，把候选写进结果里
      write_result(
        "ok" => false,
        "action" => "create_profile",
        "error" => "存在多张可用证书，请选择其中一张后重试",
        "need_certificate_selection" => true,
        "certificates" => usable.map { |c| certificate_summary(c) }
      )
      warn "[Profile] 存在 #{usable.size} 张可用证书，需要人工选择："
      usable.each_with_index { |c, i| warn "  #{i}: #{c.id}  #{c.name}  到期 #{c.expiration_date}" }
      exit 1
    end

  # ---- 3. 设备（AdHoc / Development 需要）----
  device_ids = []
  if profile_needs_devices?(profile_type)
    devices = Spaceship::ConnectAPI::Device.all.select { |d| d.status == "ENABLED" }
    device_ids = devices.map(&:id)
    puts "[Profile] 该类型需要设备，已包含 #{device_ids.size} 台"
    raise "#{profile_type} 需要至少一台已注册设备" if device_ids.empty?
  end

  # ---- 4. 同名清理 ----
  if replace
    Spaceship::ConnectAPI::Profile.all.select { |p| p.name == profile_name }.each do |old|
      puts "[Profile] 删除同名旧 Profile id=#{old.id}"
      old.delete!
    end
  end

  # ---- 5. 创建 ----
  puts "[Profile] 创建 #{profile_name} (#{profile_type}) ..."
  profile = Spaceship::ConnectAPI::Profile.create(
    name: profile_name,
    profile_type: profile_type,
    bundle_id_id: bundle_id.id,
    certificate_ids: certificates.map(&:id),
    device_ids: device_ids
  )
  puts "[Profile] 创建成功 id=#{profile.id} uuid=#{profile.uuid}"

  # ---- 6. 落盘 ----
  dir = output_dir!
  filename = "#{profile_name.gsub(/[^A-Za-z0-9_.-]/, '_')}.mobileprovision"
  File.binwrite(File.join(dir, filename), Base64.decode64(profile.profile_content))

  write_result(
    "ok" => true,
    "action" => "create_profile",
    "profile" => {
      "id" => profile.id,
      "name" => profile.name,
      "uuid" => profile.uuid,
      "type" => profile.profile_type,
      "state" => profile.profile_state,
      "expires_at" => profile.expiration_date,
      "bundle_identifier" => bundle_id.identifier
    },
    "certificates" => certificates.map { |c| certificate_summary(c) },
    "device_count" => device_ids.size,
    "files" => { "mobileprovision" => filename }
  )
end
