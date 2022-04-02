/*
 *  Copyright (C) 2022 KeePassXC Team <team@keepassxc.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import SafariServices
import os.log

let SFExtensionMessageKey = "message"
let SocketFileName = "org.keepassxc.KeePassXC.BrowserServer"
var socketFD  : Int32 = -1
var socketConnected = false
var maxMessageLength: Int32 = 1024 * 1024;

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func getSocketPath() -> String {
        let homePath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "KeePassXC")?.path
        return homePath! + "/" + SocketFileName;
    }
    
    func closeSocket() {
        if (socketFD != -1) {
            os_log(.default, "Closing socket")
            close(socketFD)
            socketFD = -1
        }
    }
    
    func connectSocket() -> Bool {
        if (socketFD != -1) {
            // Reuse socket
            return true
        }
        
        socketFD = socket(PF_LOCAL, SOCK_STREAM, 0)
        os_log(.default, "Create socket: %d" , socketFD)
        if (socketFD == -1) {
            os_log(.error, "Cannot create socket")
            return false
        }
        
        var optval: Int = 1; // Use 1 to enable the option, 0 to disable
        let status = setsockopt(socketFD, SOL_SOCKET,
            SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))
        if (status == -1) {
            os_log(.error, "setsockopt error: %d", errno)
            return false
        }

        guard setsockopt(socketFD, SOL_SOCKET, SO_SNDBUF, &maxMessageLength, socklen_t(MemoryLayout<Int32>.size(ofValue: maxMessageLength))) != -1 else {
            os_log(.error, "setsockopt error")
            return false
        }
        
        let socketPath = getSocketPath()
        os_log(.default, "Socket path: %s", socketPath)
       
        // Check if socket file exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: socketPath) {
            os_log(.default, "Socket file exists")
        } else {
            os_log(.default, "Socket file does not exist")
            return false
        }
        
        var addr = sockaddr_un()
        addr.sun_family = UInt8(AF_LOCAL)
        let lengthOfPath = socketPath.utf8.count
        guard lengthOfPath < MemoryLayout.size(ofValue: addr.sun_path) else {
            os_log(.error, "Pathname is too long")
            return false
        }
        
        strlcpy(&addr.sun_path.0, socketPath, MemoryLayout.size(ofValue: addr.sun_path))
        addr.sun_len = UInt8(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + lengthOfPath + 1)

        let sockLen = socklen_t(addr.sun_len)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, sockLen)
            }
        }
        
        if (result == -1) {
            os_log(.error, "Cannot connect socket %d", errno)
            return false
        }
        
        return true
    }
    
	func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems[0] as! NSExtensionItem
        let message = item.userInfo?[SFExtensionMessageKey]
        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@", message as! CVarArg)

        let jsonData = try? JSONSerialization.data(withJSONObject: message as! CVarArg)
        if (jsonData == nil) {
            os_log(.error, "JSON serialization error")
            return
        }
        
        let messageString = String(data: jsonData!, encoding: String.Encoding.utf8)
        if (messageString == nil)
        {
            os_log(.error, "Error parsing JSON data")
            return
        }
        
        let startIndex = messageString!.lastIndex(of: "{")
        let endIndex = messageString!.lastIndex(of: "}")
        let range = startIndex!..<endIndex!
        let sendString = String(messageString![range])
        os_log(.default, "JSON string: %s", sendString)
        
        
        if (!socketConnected) {
            if (!connectSocket()) {
                closeSocket()
                os_log(.error, "Socket not connected")
                return
            }
            
            socketConnected = true
        }

        // Send message
        let bytesWritten = write(socketFD, sendString, sendString.count)
        if (bytesWritten == -1) {
            os_log(.error, "Cannot write to socket %d", errno)
            return
        }
         
        os_log(.default, "Written %d bytes", bytesWritten)
        
        // Receive response
        var receiveBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(maxMessageLength), alignment: MemoryLayout<CChar>.size)
        let bytesRead = read(socketFD, &receiveBuffer, Int(maxMessageLength))
        if (bytesRead < MemoryLayout<UInt32>.size) {
            os_log(.error, "Error reading from socket %d", errno)
            return
        }
        
        os_log(.default, "Read %d bytes", bytesRead)
        
        // To string. Do we need a dictionary instead?
        let responseString = withUnsafePointer(to: &receiveBuffer) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: bytesRead)) {
                String(cString: $0)
            }
        }
        
        os_log(.default, "Response: %s", responseString)
        
        // Send the response to the extension
        let response = NSExtensionItem()
        response.userInfo = [ SFExtensionMessageKey: [ responseString ] ]
        context.completeRequest(returningItems: [response], completionHandler: nil)

        receiveBuffer.deallocate()
    }
}
