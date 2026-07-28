# 公共库：登录 Apple、输出目录、结果落盘
require "json"
require "base64"
require "openssl"
require "fileutils"
require "spaceship"

# 不加这行时 puts(stdout) 和 warn(stderr) 在 Actions 日志里会乱序
$stdout.sync = true
$stderr.sync = true

OUTPUT_DIR = File.expand_path("../output", __dir__)

def env(key, required: true, default: nil)
  value = ENV[key]
  value = nil if value.is_a?(String) && value.strip.empty?
  if value.nil? && default.nil? && required
    abort("[错误] 缺少必需的环境变量: #{key}")
  end
  value || default
end

# 支持两种认证方式：
#   1. App Store Connect API Key（推荐，CI 里不需要 2FA）
#   2. Apple ID + 密码（需要 FASTLANE_SESSION，否则会卡在 2FA）
def login!
  if ENV["ASC_KEY_ID"].to_s.strip.empty?
    login_with_apple_id!
  else
    login_with_api_key!
  end
end

def login_with_api_key!
  puts "[认证] 使用 App Store Connect API Key"
  token = Spaceship::ConnectAPI::Token.create(
    key_id: env("ASC_KEY_ID"),
    issuer_id: env("ASC_ISSUER_ID"),
    key: env("ASC_KEY_CONTENT")
  )
  Spaceship::ConnectAPI.token = token
  puts "[认证] 成功"
end

def login_with_apple_id!
  apple_id = env("APPLE_ID")
  password = env("APPLE_PASSWORD")
  team_id  = env("TEAM_ID", required: false)

  puts "[认证] 使用 Apple ID: #{mask_email(apple_id)}"
  if ENV["FASTLANE_SESSION"].to_s.strip.empty?
    warn "[警告] 未提供 FASTLANE_SESSION，账号若开启双重认证会登录失败。"
    warn "[警告] 本机执行 `fastlane spaceauth -u #{apple_id}` 生成后再填入。"
  end

  begin
    Spaceship::ConnectAPI.login(
      apple_id,
      password,
      use_portal: true,
      use_tunes: false,
      portal_team_id: team_id
    )
  rescue Spaceship::InvalidUserCredentialsError => e
    # Apple 返回 401 时抛这个，报错本身不区分原因，这里把常见原因列清楚
    warn ""
    warn "[排查] Apple 拒绝了这组账号密码，常见原因："
    warn "  1. 用了 App 专用密码（app-specific password）。开发者门户登录必须用 Apple 账号的真实密码，"
    warn "     App 专用密码只对上传/公证有效。"
    warn "  2. 密码本身不对。先去 https://developer.apple.com/account 手动登录验证一次。"
    warn "  3. 密码里有空格或不可见字符被一起复制进来了。"
    warn "  4. 账号被 Apple 要求改密码 / 需接受新协议，此时网页登录会有提示。"
    warn ""
    warn "[建议] 改用 App Store Connect API Key 模式，不需要密码、不受 2FA 影响、不会 30 天过期。"
    warn "       生成路径：App Store Connect → 用户和访问 → 集成 → 团队密钥"
    warn ""
    raise e
  end
  puts "[认证] 成功"
end

def mask_email(email)
  name, domain = email.to_s.split("@", 2)
  return "***" if name.nil?
  "#{name[0]}***@#{domain}"
end

def output_dir!
  FileUtils.mkdir_p(OUTPUT_DIR)
  OUTPUT_DIR
end

# 结果写到 output/result.json，前端下载 artifact 后直接解析
def write_result(payload)
  path = File.join(output_dir!, "result.json")
  File.write(path, JSON.pretty_generate(payload))
  puts "\n===== RESULT ====="
  puts JSON.pretty_generate(payload)
  puts "=================="
  path
end

# 把异常转成结构化结果，避免前端只能看到一个红叉
def run_task
  yield
rescue => e
  write_result("ok" => false, "error" => e.message, "error_class" => e.class.name)
  warn "[失败] #{e.class}: #{e.message}"
  warn e.backtrace.first(10).join("\n") if ENV["DEBUG"]
  exit 1
end

# ---- 证书类型 / Profile 类型的对应关系 ----
DISTRIBUTION_CERT_TYPES = %w[DISTRIBUTION IOS_DISTRIBUTION MAC_APP_DISTRIBUTION].freeze
DEVELOPMENT_CERT_TYPES  = %w[DEVELOPMENT IOS_DEVELOPMENT MAC_APP_DEVELOPMENT].freeze

def cert_types_for_profile(profile_type)
  if profile_type.to_s.include?("DEVELOPMENT")
    DEVELOPMENT_CERT_TYPES
  else
    DISTRIBUTION_CERT_TYPES
  end
end

def profile_needs_devices?(profile_type)
  profile_type.to_s.include?("DEVELOPMENT") || profile_type.to_s.include?("ADHOC")
end

def certificate_summary(cert)
  {
    "id" => cert.id,
    "name" => cert.name,
    "display_name" => cert.display_name,
    "type" => cert.certificate_type,
    "platform" => cert.platform,
    "serial" => cert.serial_number,
    "expires_at" => cert.expiration_date
  }
end
