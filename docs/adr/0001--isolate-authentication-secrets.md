# 隔离认证秘密与普通配置

- **状态**：Active / implemented
- **日期**：2026-09-25
- **范围**：LinkUp Android 客户端的认证配置持久化

## Problem

认证配置同时包含普通网络参数和校园网凭据。旧实现把凭据写入普通 JSON，设置页面通过读取完整 Map 再覆盖写回，既无法明确表达局部更新，也使明文凭据暴露在普通文件、日志和备份路径中。升级已有安装时还需要在不丢失凭据的情况下迁移数据。

## Decision

`ConfigRepository` 作为认证配置的唯一持久化入口，负责普通 JSON 与秘密存储的组合读取、目标字段更新、初始保存和删除。调用方使用 `AuthConfig` 与 `ConfigUpdate`，不再自行合并或覆盖完整 JSON。字符串更新遵循 `null=保留、空字符串=清空、非空=覆盖`；认证服务器空值归一化为明确默认值。

校园网密码通过 `SecretStore` 保存。生产实现使用 `flutter_secure_storage` 的 Android Keystore 支持，并使用独立的 `linkup_auth` 命名空间。普通 JSON 只保存非敏感字段，密码不会进入其序列化结果、日志或异常文本。

升级迁移遵循固定顺序：先把旧 JSON 中的密码写入 `SecretStore`，再读回并校验；只有两步都成功后才移除普通 JSON 中的密码字段。任一步失败都保留旧文件并返回可重试错误。密码更新只写秘密存储；删除操作分别尝试删除普通配置和秘密，任一失败都返回失败，后续调用可以重试。

Android 禁用应用备份，并在 Android 12 及更早版本的备份规则中排除 `linkup_auth` 秘密存储命名空间和迁移期间的 `app_flutter/linkup_config.json`，避免恢复当前设备 Keystore 无法解密的密文或尚未迁移的明文凭据。

## Alternatives considered

- **继续把密码写入普通 JSON，并依赖日志遮罩**：不能建立存储边界，日志遮罩也无法覆盖文件、备份和异常路径，因此不采用。
- **使用普通 `SharedPreferences` 或自定义未绑定 Keystore 的文件保存密码**：实现简单，但不满足 Android Keystore 保护要求，因此不采用。
- **由调用方读取完整配置 Map 后覆盖写回**：无法区分未提供字段与明确清空，容易恢复旧 `user_type` 或覆盖并发的其他更新，因此不采用。
- **在 Flutter 之外自行实现 MethodChannel Keystore 适配器**：可以减少依赖，但需要维护额外的 Android 加密、迁移和错误语义；当前插件已经提供所需 Android 能力，因此不采用。

## Consequences / Risks

- 普通配置和秘密存储是两个独立的故障域。仓库通过写入顺序、读回校验和双删除结果避免静默丢失；跨存储操作本身仍不能提供事务回滚。
- Android Keystore 密钥丢失、卸载重装或恢复到无法使用原密钥的设备后，用户需要重新输入凭据。备份规则不能恢复不可解密的秘密，这是有意的安全边界。
- `flutter_secure_storage` 是新增依赖；当前项目只承诺 Android 行为，其他平台模板不作为本决策的验证范围。
- 仓库测试通过注入文件和 `SecretStore` 验证首次保存、局部更新、迁移、密码变更和删除重试；Android 备份安全性由 Manifest 与 XML 规则验证。

## Reintroduction conditions

只有在重新评估 Android Keystore 兼容性、备份威胁模型和迁移恢复流程后，才可以替换秘密存储实现或取消普通配置与秘密存储的隔离。替换实现必须保留写入后读回校验、失败可重试删除和普通 JSON 不含秘密字段的约束。
