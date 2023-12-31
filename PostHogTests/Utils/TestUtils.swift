@testable import Nimble
import Nocilla
import PostHog

class PHGPassthroughMiddleware: PHGMiddleware {
  var lastContext: PHGContext?
//  Catch more than just the latest context
  var allContexts = [PHGContext]()
  
  func context(_ context: PHGContext, next: @escaping PHGMiddlewareNext) {
    allContexts.append(context)
    lastContext = context;
    next(context)
  }
}

class TestMiddleware: PHGMiddleware {
  var lastContext: PHGContext?
  var swallowEvent = false
  func context(_ context: PHGContext, next: @escaping PHGMiddlewareNext) {
    lastContext = context
    if !swallowEvent {
      next(context)
    }
  }
}

extension PHGPostHog {
  func test_payloadManager() -> PHGPayloadManager? {
    return self.value(forKey: "payloadManager") as? PHGPayloadManager
  }
}

extension PHGPayloadManager {
  func test_postHogIntegration() -> PHGPostHogIntegration? {
    return self.value(forKey: "integration") as? PHGPostHogIntegration
  }
}

extension PHGPostHogIntegration {
  func test_fileStorage() -> PHGFileStorage? {
    return self.value(forKey: "fileStorage") as? PHGFileStorage
  }
  func test_referrer() -> String? {
    return self.value(forKey: "referrer") as? String
  }
  func test_distinctId() -> String? {
    return self.value(forKey: "distinctId") as? String
  }
  func test_flushTimer() -> Timer? {
    return self.value(forKey: "flushTimer") as? Timer
  }
  func test_batchRequest() -> URLSessionUploadTask? {
    return self.value(forKey: "batchRequest") as? URLSessionUploadTask
  }
  func test_queue() -> [AnyObject]? {
    return self.value(forKey: "queue") as? [AnyObject]
  }
  func test_dispatchBackground(block: @escaping @convention(block) () -> Void) {
    self.perform(Selector(("dispatchBackground:")), with: block)
  }
}


class JsonGzippedBody : LSMatcher, LSMatcheable {
    
    let expectedJson: AnyObject
    
    init(_ json: AnyObject) {
        self.expectedJson = json
    }
    
    func matchesJson(_ json: AnyObject) -> Bool {
        let actualValue : () -> NSObject = {
            return json as! NSObject
        }
        let failureMessage = FailureMessage()
        let location = SourceLocation()
        let matches = Nimble.equal(expectedJson).matches(actualValue, failureMessage: failureMessage, location: location)
//        print("matches=\(matches) expected \(expectedJson) actual \(json)")
        return matches
    }
    
    override func matches(_ string: String!) -> Bool {
        if let data = string.data(using: String.Encoding.utf8),
            let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            return matchesJson(json as AnyObject)
        }
        return false
    }
    
    override func matchesData(_ data: Data!) -> Bool {
        if let data = (data as NSData).phg_gunzipped(),
            let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            return matchesJson(json as AnyObject)
        }
        return false
    }
    
    func matcher() -> LSMatcher! {
        return self
    }
    
    func expectedHeaders() -> [String:String] {
        let data = try? JSONSerialization.data(withJSONObject: expectedJson, options: [])
        let contentLength = (data as NSData?)?.phg_gzipped()?.count ?? 0
        return [
            "Content-Encoding": "gzip",
            "Content-Type": "application/json",
            "Content-Length": "\(contentLength)",
            // Accept-Encoding technically doesn't belong here because
            // sending json body doesn't necessarily mean expecting JSON response. But
            // there isn't anywhere else that's suitable and we don't exactly want to copy paste this logic many times over
            // So will leave it here for now.
            "Accept-Encoding": "gzip",
        ]
    }
}

typealias AndJsonGzippedBodyMethod = (AnyObject) -> LSStubRequestDSL

extension LSStubRequestDSL {
    var withJsonGzippedBody: AndJsonGzippedBodyMethod {
        return { json in
            let body = JsonGzippedBody(json)
            return self
                .withHeaders(body.expectedHeaders())!
                .withBody(body)!
        }
    }
}

class TestApplication: NSObject, PHGApplicationProtocol {
  class BackgroundTask {
    let identifier: UInt
    var isEnded = false
    
    init(identifier: UInt) {
      self.identifier = identifier
    }
  }
  
  var backgroundTasks = [BackgroundTask]()
  
  // MARK: - PHGApplicationProtocol
  var delegate: UIApplicationDelegate? = nil

  func phg_beginBackgroundTask(withName taskName: String?, expirationHandler handler: (() -> Void)? = nil) -> UInt {
    let backgroundTask = BackgroundTask(identifier: (backgroundTasks.map({ $0.identifier }).max() ?? 0) + 1)
    backgroundTasks.append(backgroundTask)
    return backgroundTask.identifier
  }
  
  func phg_endBackgroundTask(_ identifier: UInt) {
    guard let index = backgroundTasks.index(where: { $0.identifier == identifier }) else { return }
    backgroundTasks[index].isEnded = true
  }
}
