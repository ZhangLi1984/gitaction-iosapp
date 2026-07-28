# 创建 Distribution / Development 证书
#
# 流程：本地生成私钥 -> 生成 CSR -> 提交 Apple -> 拿回 .cer
#      -> 私钥 + .cer 合成 .p12（不合成的话这张证书没有私钥，是废的）
#
# 环境变量：
#   CERTIFICATE_TYPE  DISTRIBUTION | IOS_DISTRIBUTION | DEVELOPMENT | IOS_DEVELOPMENT
#   P12_PASSWORD      导出 .p12 的密码（必填）
#   COMMON_NAME       CSR 的 CN，可选
require_relative "common"

run_task do
  cert_type   = env("CERTIFICATE_TYPE", default: "DISTRIBUTION")
  p12_password = env("P12_PASSWORD")
  common_name = env("COMMON_NAME", required: false, default: "apple-dev-tool")

  login!

  # ---- 1. 私钥 + CSR ----
  puts "[证书] 生成 2048 位 RSA 私钥与 CSR"
  key = OpenSSL::PKey::RSA.new(2048)
  csr = OpenSSL::X509::Request.new
  csr.version = 0
  csr.subject = OpenSSL::X509::Name.new([
    ["CN", common_name, OpenSSL::ASN1::UTF8STRING],
    ["C",  "US",        OpenSSL::ASN1::PRINTABLESTRING]
  ])
  csr.public_key = key.public_key
  csr.sign(key, OpenSSL::Digest::SHA256.new)

  # ---- 2. 提交给 Apple ----
  existing = Spaceship::ConnectAPI::Certificate.all(
    filter: { certificateType: cert_type }
  )
  puts "[证书] 该类型已有 #{existing.size} 张：#{existing.map(&:name).join(', ')}"

  puts "[证书] 创建 #{cert_type} ..."
  cert = Spaceship::ConnectAPI::Certificate.create(
    certificate_type: cert_type,
    csr_content: csr.to_pem
  )
  puts "[证书] 创建成功 id=#{cert.id} name=#{cert.name}"

  # ---- 3. 落盘 ----
  dir = output_dir!
  der = Base64.decode64(cert.certificate_content)
  x509 = OpenSSL::X509::Certificate.new(der)

  base = "#{cert_type.downcase}_#{cert.serial_number || cert.id}"
  cer_path = File.join(dir, "#{base}.cer")
  key_path = File.join(dir, "#{base}.key.pem")
  p12_path = File.join(dir, "#{base}.p12")

  File.binwrite(cer_path, der)
  File.write(key_path, key.to_pem)

  # OpenSSL 3 默认用 AES 加密 p12，macOS 12+ 钥匙串可以导入；
  # 老系统需要 3DES，失败时回退。
  p12 =
    begin
      OpenSSL::PKCS12.create(p12_password, cert.name || base, key, x509)
    rescue OpenSSL::PKCS12::PKCS12Error => e
      warn "[证书] 默认算法导出 p12 失败(#{e.message})，回退 3DES"
      OpenSSL::PKCS12.create(p12_password, cert.name || base, key, x509,
                             "PBE-SHA1-3DES", "PBE-SHA1-3DES")
    end
  File.binwrite(p12_path, p12.to_der)

  write_result(
    "ok" => true,
    "action" => "create_certificate",
    "certificate" => certificate_summary(cert),
    "files" => {
      "cer" => File.basename(cer_path),
      "private_key" => File.basename(key_path),
      "p12" => File.basename(p12_path)
    },
    "note" => "p12 密码为你在网页上填写的 P12 密码；私钥仅存在于本次 artifact，请立刻下载保存。"
  )
end
