//
//  BitlyClient.swift
//  Cast
//
//  Created by Leonardo on 23/08/2015.
//  Copyright © 2015 Leonardo Faoro. All rights reserved.
//

import Cocoa
import RxSwift
import RxCocoa
import SwiftyJSON

public class BitlyClient {
    
    public class func shortenURL(URL: NSURL) -> Observable<NSURL> {
        let bitlyAPIurl = "https://api-ssl.bitly.com"
        let bitlyAPIshorten = bitlyAPIurl + "/v3/shorten?access_token=" + bitlyOAuth2Token + "&longUrl=" + URL.relativeString!
        let url = NSURL(string: bitlyAPIshorten)!
        
        return create { stream in
            let session = NSURLSession.sharedSession()
            session.dataTaskWithURL(url) { (data, response, error) in
                if let data = data {
                    let jsonData = JSON(data: data)
                    let statusCode = jsonData["status_code"].int
                    if statusCode == 200 {
                        if let shortenedURL = jsonData["data"]["url"].URL {
                            sendNext(stream, shortenedURL)
                            sendCompleted(stream)
                        }
                    } else {
                        sendError(stream, ConnectionError.StatusCode(jsonData["status_code"].int!))
                    }
                } else {
                    sendError(stream, ConnectionError.NoResponse((error!.localizedDescription)))
                }
                }.resume()
            
            return NopDisposable.instance
        }
    }
}