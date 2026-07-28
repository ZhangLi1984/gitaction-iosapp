# Apple Developer 自动化 · 执行端

这个仓库只放执行端：GitHub Actions 工作流 + Ruby(spaceship) 脚本。
控制台网页在本地运行，不在这个仓库里。

## 目录

```
.github/
├── actions/setup-apple/action.yml   # 复合 Action：Ruby + fastlane + 凭据解析
└── workflows/
    ├── create_certificate.yml       # 私钥+CSR → .cer → .p12
    ├── create_bundleid.yml
    ├── create_profile.yml           # 含证书数量判断
    └── list_resources.yml           # 拉全部资源给网页
scripts/
├── common.rb                        # 登录 / 输出 / 错误包装
├── prepare_credentials.rb           # 凭据 JSON → 打码 → 环境变量
├── create_certificate.rb
├── create_bundle_id.rb
├── create_profile.rb
└── list_resources.rb
```

## 一、准备 Apple 凭据

**默认：App Store Connect API Key**（CI 里不需要 2FA，不会 30 天过期）

1. App Store Connect → 用户和访问 → 集成 → **团队密钥** → 生成密钥，角色必须选 **Admin**

   ⚠️ 只有 **Account Holder / Admin** 能创建证书、注册 App ID、创建 Profile。
   **App Manager 和 Developer 角色不行**——即使在「用户和访问」里单独勾了
   Certificates, Identifiers & Profiles，也只是有限访问，建不了证书和 Profile。
   角色选错的话本工具四个任务里有三个会失败。
2. 下载 `AuthKey_XXXX.p8`（只能下一次），记下 Key ID 和 Issuer ID
3. 拼成 JSON：

```json
{"mode":"api_key","key_id":"ABC123DEFG","issuer_id":"57246542-96fe-1a63-e053-0824d011072a","key":"-----BEGIN PRIVATE KEY-----\nMIGT...\n-----END PRIVATE KEY-----"}
```

**备选：Apple ID + 密码**（账号开了双重认证就必须带 session）

```bash
gem install fastlane
fastlane spaceauth -u you@example.com   # 输出一大段 YAML，整段复制
```

```json
{"mode":"apple_id","apple_id":"you@example.com","password":"...","team_id":"ABCDE12345","session":"---\n- !ruby/object:HTTP::Cookie ..."}
```

Session 约 30 天过期，过期后工作流会突然开始失败且报错很不直观。网页上有「清空 Session」按钮。

## 二、配置仓库

1. 把本目录的**内容**推到仓库根目录（`.github/` 必须在根）
   工作流还必须在**默认分支**上，`workflow_dispatch` 才会生效，否则 dispatch API 返回 404
2. 可选：`Settings → Secrets and variables → Actions → New repository secret`
   名称 `APPLE_CREDENTIALS`，值填上面的 JSON
   —— 只有用「仓库 Secret」模式才需要；默认的 API Key 模式在网页上直接填
3. 可选：`Variables` 里加 `RUNNER_LABEL=ubuntu-latest`
   —— 这几个任务只调 Apple 的 HTTP API，不需要 Xcode，Linux 又快又便宜（macOS 分钟数按 10 倍计费）

## 三、GitHub Token（给本地网页用）

`Settings → Developer settings → Personal access tokens → Fine-grained tokens`

- Repository access：`Only select repositories` → 只勾这一个仓库
- Repository permissions：只需 **`Actions: Read and write`**
  （`Metadata: Read-only` 会自动勾上且不能取消，正常；其余全部保持 No access）

控制台用到的 6 个接口全部归 Actions 权限：dispatch 要 write，查运行/查产物/下载产物要 read。

签发后填进本地网页，**不要写进任何文件推上来**。

## 四、几个关键设计

**证书为什么会自动生成 .p12**
证书私钥是在 Runner 上生成 CSR 时产生的。只拿 `.cer` 而没有那把私钥，证书是废的、无法签名。
所以工作流直接用私钥 + `.cer` 合成好 `.p12` 一起放进产物。
含私钥的产物 `retention-days: 1`，**跑完请立刻下载**。

**Profile 的证书选择逻辑**（`scripts/create_profile.rb`）

| 可用证书数 | 行为 |
|---|---|
| 0 | 报错，提示先建证书 |
| 1 | 自动选择 |
| >1 | 失败，把候选写进 `result.json`，网页弹出下拉让你选，选完自动重跑 |

指定了 `certificate_ids` 就跳过判断直接用。

**任务与运行的对应**
GitHub 的 dispatch API 不返回 run id。网页每次生成 `request_id`，工作流的 `run-name` 带上它，
网页轮询 `/actions/runs` 用它匹配——这是标准绕法。

**凭据传递**
`workflow_dispatch` 最多 10 个输入，所以凭据打包成单个 `credentials` JSON 输入；
留空时工作流回落到仓库 Secret `APPLE_CREDENTIALS`。
`prepare_credentials.rb` 解析后用 `::add-mask::` 打码再写入 `$GITHUB_ENV`。

⚠️ 从网页传的凭据会出现在**运行详情页的输入参数区**（日志已打码，但输入区不受保护），同仓库协作者可见。
个人自用可接受；多人协作请改用仓库 Secret 模式。

## 五、后续扩展

- **上传/提审**：加 `upload_appstore.yml`，`fastlane deliver`（这一步必须用 macOS Runner）
- **设备注册**：`Spaceship::ConnectAPI::Device.create(name:, platform:, udid:)`
- **Capabilities**：`bundle_id.create_capability(...)`（推送、支付等）
- **多账号**：把 `APPLE_CREDENTIALS` 拆成多个 Secret，工作流加一个 `account` 输入去选

## 六、常见错误

| 报错 | 原因 |
|---|---|
| 找不到运行记录 / dispatch 404 | 工作流不在默认分支上 |
| `缺少必需的环境变量` | 凭据 JSON 字段不全，或 Secret 没配 |
| `Authentication credentials are missing or invalid` | `.p8` 粘贴时丢了换行，或 Key ID / Issuer ID 填错 |
| `403 FORBIDDEN` / `not permitted` | API Key 角色不是 Admin。证书、App ID、Profile 只有 Account Holder / Admin 能建 |
| 卡在登录 / 要验证码 | Apple ID 模式没给 `FASTLANE_SESSION`，或 session 过期 |
| `maximum number of certificates` | Distribution 证书上限 2~3 张，去 Portal 吊销旧的 |
| `There is no App ID with ID` | 先跑创建 Bundle ID |
