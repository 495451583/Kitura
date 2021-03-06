/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import XCTest
import Kitura

@testable import KituraNet

import Foundation
import Dispatch

enum SSLOption {
    case both
    case httpOnly
    case httpsOnly
}

class KituraTest: XCTestCase {

    static let httpPort = 8080
    static let httpsPort = 8443

    static private(set) var httpServer: HTTPServer? = nil
    static private(set) var httpsServer: HTTPServer? = nil

    private(set) var port = -1
    private(set) var useSSL = false

    static let sslConfig: SSLConfig = {
        let path = #file
        let sslConfigDir: String
        if let range = path.range(of: "/", options: .backwards) {
            sslConfigDir = path.substring(to: range.lowerBound) + "/SSLConfig/"
        } else {
            sslConfigDir = "./SSLConfig/"
        }

        #if os(Linux)
            let certificatePath = sslConfigDir + "certificate.pem"
            let keyPath = sslConfigDir + "key.pem"
            return SSLConfig(withCACertificateDirectory: nil, usingCertificateFile: certificatePath,
                             withKeyFile: keyPath, usingSelfSignedCerts: true)
        #else
            let chainFilePath = sslConfigDir + "certificateChain.pfx"
            return SSLConfig(withChainFilePath: chainFilePath, withPassword: "kitura",
                             usingSelfSignedCerts: true)
        #endif
    }()

    private static let initOnce: () = {
        PrintLogger.use(colored: true)
    }()

    override func setUp() {
        super.setUp()
        KituraTest.initOnce
    }

    func performServerTest(_ router: ServerDelegate, sslOption: SSLOption = SSLOption.both,
                           line: Int = #line, asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        if sslOption != SSLOption.httpsOnly {
            self.port = KituraTest.httpPort
            self.useSSL = false
            doPerformServerTest(router: router, line: line, asyncTasks: asyncTasks)
        }

        if sslOption != SSLOption.httpOnly {
            self.port = KituraTest.httpsPort
            self.useSSL = true
            doPerformServerTest(router: router, line: line, asyncTasks: asyncTasks)
        }
    }

    func doPerformServerTest(router: ServerDelegate, line: Int, asyncTasks: [(XCTestExpectation) -> Void]) {

        guard startServer(router: router) else {
            XCTFail("Error starting server on port \(port). useSSL:\(useSSL)")
            return
        }

        let requestQueue = DispatchQueue(label: "Request queue")
        for (index, asyncTask) in asyncTasks.enumerated() {
            let expectation = self.expectation(line: line, index: index)
            requestQueue.async() {
                asyncTask(expectation)
            }
        }

        // wait for timeout or for all created expectations to be fulfilled
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    private func startServer(router: ServerDelegate) -> Bool {
        if useSSL {
            if let server = KituraTest.httpsServer {
                server.delegate = router
                return true
            }
        } else {
            if let server = KituraTest.httpServer {
                server.delegate = router
                return true
            }
        }

        let server = HTTP.createServer()
        server.delegate = router
        if useSSL {
            server.sslConfig = KituraTest.sslConfig.config
        }

        do {
            try server.listen(on: port)

            if useSSL {
                KituraTest.httpsServer = server
            } else {
                KituraTest.httpServer = server
            }
            return true
        } catch {
            XCTFail("Error starting server: \(error)")
            return false
        }
    }

    func stopServer() {
        KituraTest.httpServer?.stop()
        KituraTest.httpServer = nil

        KituraTest.httpsServer?.stop()
        KituraTest.httpsServer = nil
    }

    func performRequest(_ method: String, path: String, port: Int? = nil, useSSL: Bool? = nil,
                        callback: @escaping ClientRequest.Callback, headers: [String: String]? = nil,
                        requestModifier: ((ClientRequest) -> Void)? = nil) {

        let port = Int16(port ?? self.port)
        let useSSL = useSSL ?? self.useSSL

        var allHeaders = [String: String]()
        if  let headers = headers {
            for  (headerName, headerValue) in headers {
                allHeaders[headerName] = headerValue
            }
        }
        if allHeaders["Content-Type"] == nil {
            allHeaders["Content-Type"] = "text/plain"
        }

        let schema = useSSL ? "https" : "http"
        var options: [ClientRequest.Options] =
                [.method(method), .schema(schema), .hostname("localhost"), .port(port), .path(path),
                 .headers(allHeaders)]
        if useSSL {
            options.append(.disableSSLVerification)
        }

        let req = HTTP.request(options, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end(close: true)
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)](ssl:\(useSSL))")
    }
}
