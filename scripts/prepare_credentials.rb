# 解析凭据 JSON -> 打码 -> 写入 $GITHUB_ENV，供后续步骤使用
#
# 输入（环境变量 CREDENTIALS，取自 workflow 输入或仓库 Secret）：
#   API Key 方式：
#     {"mode":"api_key","key_id":"XXX","issuer_id":"xxx-xxx","key":"-----BEGIN PRIVATE KEY-----\n..."}
#   Apple ID 方式：
#     {"mode":"apple_id","apple_id":"a@b.com","password":"xxx","team_id":"ABCDE","session":"---\n- !ruby/object..."}
require "json"

raw = ENV["CREDENTIALS"].to_s.strip
abort("[错误] 未提供凭据：请在网页中填写，或配置仓库 Secret APPLE_CREDENTIALS") if raw.empty?

begin
  creds = JSON.parse(raw)
rescue JSON::ParserError => e
  abort("[错误] 凭据不是合法 JSON: #{e.message}")
end

github_env = ENV["GITHUB_ENV"] or abort("[错误] 只能在 GitHub Actions 中运行")

# 让所有敏感值在日志里变成 ***
def mask(value)
  value.to_s.split("\n").each do |line|
    line = line.strip
    puts "::add-mask::#{line}" if line.length >= 4
  end
end

def export(file, key, value, secret: false)
  return if value.to_s.strip.empty?
  mask(value) if secret
  if value.to_s.include?("\n")
    delimiter = "GHEOF_#{key}"
    File.open(file, "a") { |f| f.puts("#{key}<<#{delimiter}\n#{value}\n#{delimiter}") }
  else
    File.open(file, "a") { |f| f.puts("#{key}=#{value}") }
  end
end

mode = creds["mode"].to_s
mode = creds["key_id"].to_s.empty? ? "apple_id" : "api_key" if mode.empty?

case mode
when "api_key"
  %w[key_id issuer_id key].each do |k|
    abort("[错误] API Key 模式缺少字段: #{k}") if creds[k].to_s.strip.empty?
  end
  export(github_env, "ASC_KEY_ID", creds["key_id"])
  export(github_env, "ASC_ISSUER_ID", creds["issuer_id"])
  export(github_env, "ASC_KEY_CONTENT", creds["key"], secret: true)
  puts "[凭据] 模式 = App Store Connect API Key (key_id=#{creds['key_id']})"
when "apple_id"
  %w[apple_id password].each do |k|
    abort("[错误] Apple ID 模式缺少字段: #{k}") if creds[k].to_s.strip.empty?
  end
  export(github_env, "APPLE_ID", creds["apple_id"])
  export(github_env, "APPLE_PASSWORD", creds["password"], secret: true)
  export(github_env, "TEAM_ID", creds["team_id"])
  export(github_env, "FASTLANE_SESSION", creds["session"], secret: true)
  # fastlane 用这两个变量做非交互登录
  export(github_env, "FASTLANE_USER", creds["apple_id"])
  export(github_env, "FASTLANE_PASSWORD", creds["password"], secret: true)
  puts "[凭据] 模式 = Apple ID (#{creds['apple_id'].to_s.sub(/(?<=.).*(?=@)/, '***')})"
else
  abort("[错误] 未知的凭据模式: #{mode}")
end
