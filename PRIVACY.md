# 隐私政策

Yomi 可在 Android、Windows、Linux 平台使用，并配套一个精美的网页版。

*   [Matrix 协议](#matrix)
*   [数据库](#database)
*   [加密机制](#encryption)
* [应用权限](#app-permissions)
*   [推送通知](#push-notifications)

## Matrix 协议 <a id="matrix"/>
Yomi 采用 Matrix 协议。这意味着 Yomi 仅是客户端，可连接至任何兼容的 Matrix 服务器。为方便使用，Yomi 使用梨的 Matrix 服务器作为默认服务器。

Yomi 仅与选定服务器及 [OpenStreetMap](https://openstreetmap.org)（用于地图显示）进行通信。

更多信息请访问：[https://matrix.org](https://matrix.org)

## 数据库 <a id="database"/>
Yomi 会在用户设备的本地 sqflite 数据库中缓存从服务器接收的部分数据。网页版使用 indexedDB。Yomi 始终通过 SQLCipher 加密数据库，并将密钥存储在设备的[安全存储区](https://pub.dev/packages/flutter_secure_storage)。

更多信息请访问：[https://pub.dev/packages/sqflite](https://pub.dev/packages/sqflite) 与 [https://pub.dev/packages/sqlcipher_flutter_libs](https://pub.dev/packages/sqlcipher_flutter_libs)

## 加密机制 <a id="encryption"/>
Yomi 与任何服务器之间的所有实质内容通信均采用传输加密机制进行安全保护。

Yomi 默认在私聊中启用[端到端加密](https://gitlab.matrix.org/matrix-org/olm)，通过 libolm 实现。

## 应用权限 <a id="app-permissions"/>

以下是 Android 权限说明：

#### 网络访问权限
Yomi 需联网才能与 Matrix 服务器通信。

#### 振动权限
Yomi 使用振动进行本地通知。相关实现详见：[https://pub.dev/packages/flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)

#### 录音权限
Yomi 支持在聊天中发送语音消息，因此需要录音权限。

#### 写入外部存储权限
用户可保存接收的文件，故应用需要此权限。

#### 读取外部存储权限
用户可从设备文件系统发送文件。

#### 定位权限
Yomi 支持通过聊天共享实时位置。用户共享位置时，将调用设备定位服务并通过 Matrix 发送地理数据。