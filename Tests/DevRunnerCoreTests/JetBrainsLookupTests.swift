import XCTest
@testable import DevRunnerCore

final class JetBrainsLookupTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = try! TestSupport.makeDirectory()
    }

    override func tearDown() {
        TestSupport.remove(root)
        super.tearDown()
    }

    func testApplicationServersHomeAndJdkTable() throws {
        let servers = root.appendingPathComponent("applicationServers.xml")
        let jdks = root.appendingPathComponent("jdk.table.xml")
        try TestSupport.write("""
        <application>
          <component name="ApplicationServersManager">
            <ServerSettings>
              <option name="SERVERS">
                <list>
                  <ServerSettingsImpl>
                    <option name="NAME" value="Tomcat 9.0.41" />
                    <option name="HOME" value="/Users/dev/Documents/Progetti/apache-tomcat-9.0.41" />
                  </ServerSettingsImpl>
                </list>
              </option>
            </ServerSettings>
          </component>
        </application>
        """, to: servers)
        try TestSupport.write("""
        <application>
          <component name="ProjectJdkTable">
            <jdk version="2">
              <name value="corretto-1.8" />
              <homePath value="$USER_HOME$/Library/Java/JavaVirtualMachines/corretto-1.8.jdk/Contents/Home" />
            </jdk>
          </component>
        </application>
        """, to: jdks)
        let home = URL(fileURLWithPath: "/Users/dev")
        let project = URL(fileURLWithPath: "/proj")
        XCTAssertEqual(
            JetBrainsLookup.catalinaHome(serverName: "Tomcat 9.0.41", files: [servers], projectRoot: project, userHome: home),
            "/Users/dev/Documents/Progetti/apache-tomcat-9.0.41"
        )
        XCTAssertEqual(
            JetBrainsLookup.jdkHome(name: "corretto-1.8", files: [jdks], projectRoot: project, userHome: home),
            "/Users/dev/Library/Java/JavaVirtualMachines/corretto-1.8.jdk/Contents/Home"
        )
        XCTAssertNil(JetBrainsLookup.catalinaHome(serverName: "Manca", files: [servers], projectRoot: project, userHome: home))
    }

    func testJavaEEServersFileAndAbsoluteJre() throws {
        let servers = root.appendingPathComponent("javaeeAppServers.xml")
        try TestSupport.write("""
        <application>
          <component name="AppserversManager">
            <ServerDK NAME="Tomcat 9.0.41">
              <DATA>
                <option name="CATALINA_HOME" value="$USER_HOME$/Documents/Progetti/apache-tomcat-9.0.41" />
              </DATA>
            </ServerDK>
          </component>
        </application>
        """, to: servers)
        let home = URL(fileURLWithPath: "/Users/dev")
        let project = URL(fileURLWithPath: "/proj")
        XCTAssertEqual(
            JetBrainsLookup.catalinaHome(serverName: "Tomcat 9.0.41", files: [servers], projectRoot: project, userHome: home),
            "/Users/dev/Documents/Progetti/apache-tomcat-9.0.41"
        )
        XCTAssertEqual(
            JetBrainsLookup.jdkHome(name: "/opt/java", files: [], projectRoot: project, userHome: home),
            "/opt/java"
        )
    }

    func testDiscoverReadsJetBrainsOptions() throws {
        let options = root
            .appendingPathComponent("Library/Application Support/JetBrains/IntelliJIdeaTest/options")
        let servers = options.appendingPathComponent("applicationServers.xml")
        let jdks = options.appendingPathComponent("jdk.table.xml")
        try TestSupport.write("<application/>", to: servers)
        try TestSupport.write("<application/>", to: jdks)
        let found = JetBrainsLookup.discover(userHome: root)
        XCTAssertEqual(found.servers.map(\.lastPathComponent), ["applicationServers.xml"])
        XCTAssertEqual(found.jdks.map(\.lastPathComponent), ["jdk.table.xml"])
        XCTAssertTrue(found.servers.first?.path.contains("IntelliJIdeaTest/options/applicationServers.xml") == true)
        XCTAssertTrue(found.jdks.first?.path.contains("IntelliJIdeaTest/options/jdk.table.xml") == true)
    }

    func testShellQuoteLeavesSafeTokens() {
        XCTAssertEqual(ShellWords.quote("dev"), "dev")
        XCTAssertEqual(ShellWords.quote("a b"), "'a b'")
        XCTAssertEqual(MacroExpander.expand("$PROJECT_DIR$/app.py", projectRoot: URL(fileURLWithPath: "/proj"), userHome: URL(fileURLWithPath: "/Users/dev")), "/proj/app.py")
    }
}
