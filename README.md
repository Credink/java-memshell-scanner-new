# java-memshell-scanner-new

基于 [c0ny1/java-memshell-scanner](https://github.com/c0ny1/java-memshell-scanner) 的 Tomcat 内存马扫描/查杀 JSP。

将 `tomcat-memshell-scanner.jsp` 部署到目标 Web 应用后访问即可。**仅用于授权应急响应。**

## 当前版本 0.2.1

### 支持类型

| 类型 | 扫描 | 查杀 | 说明 |
|------|------|------|------|
| Filter | ✅ | ✅ | 同步清理 filterDefs / filterMaps / filterConfigs |
| Servlet | ✅ | ✅ | 支持多 urlPattern |
| Listener | ✅ | ✅ | Event + Lifecycle，不限于 ServletRequestListener |
| Valve | ✅ | ✅ | Context / Host / Engine；内置 Valve 受保护 |
| WebSocket | ✅ | ✅ | exact + template 匹配；兼容 javax / jakarta |
| Timer | ✅ | ✅ | TimerThread 队列任务 |
| Upgrade | ✅ | ✅ | AbstractHttp11Protocol.httpUpgradeProtocols |
| ExecutorShell | ✅ | ✅ | 检测非标准 Executor 并可恢复 |

### 兼容性改进

- 反射获取 `StandardContext`（Catalina Request / Facade / ServletContext / session 多路径）
- 自动解包 Spring/Filter 的 RequestWrapper，降低内嵌 Tomcat 取 Context 失败概率
- `trySetAccessible` + 按实参兼容查找方法，减少 Tomcat 版本间方法签名差异导致的失败
- 避免硬编码 Tomcat / WebSocket 类型；WebSocket 属性兼容 javax / jakarta
- FilterMap URL：兼容 Tomcat 6 的 `getURLPattern()` 与 7+ 的 `getURLPatterns()`
- Filter 未实例化时回退展示 `filterDef.filterClass`，避免漏报
- class dump：多 ClassLoader 加载 → 资源流 → BCEL → Arthas 提示；写出流用反射，降低 API 包名差异
- 分区 try/catch，单模块失败不中断整页扫描
- JDK16+ 访问 `java.util.Timer` 内部字段可能被模块系统拦截，页面会提示 `--add-opens`

### 已知限制

- Agent / `redefineClasses` 型内存马无法通过本 JSP 卸载
- 纯内存 defineClass 且无磁盘资源时，dump 可能失败
- Spring MVC Interceptor / Controller 需另行排查
- 非 Tomcat 容器（Jetty / Undertow / WebLogic 等）不在本 JSP 覆盖范围
- 学习/应急产物，请在隔离环境验证后再用于生产
