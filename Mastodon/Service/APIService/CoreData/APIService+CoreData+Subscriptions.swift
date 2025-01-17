//
//  APIService+CoreData+Notification.swift
//  Mastodon
//
//  Created by ihugo on 2021/4/11.
//

import os.log
import Foundation
import CoreData
import CoreDataStack
import MastodonSDK

extension APIService.CoreData {
    
    static func createOrFetchSubscription(
        into managedObjectContext: NSManagedObjectContext,
        setting: Setting,
        policy: Mastodon.API.Subscriptions.Policy
    ) -> (subscription: Subscription, isCreated: Bool) {
        let oldSubscription: Subscription? = {
            let request = Subscription.sortedFetchRequest
            request.predicate = Subscription.predicate(policyRaw: policy.rawValue)
            request.fetchLimit = 1
            request.returnsObjectsAsFaults = false
            return managedObjectContext.safeFetch(request).first
        }()
        
        if let oldSubscription = oldSubscription {
            oldSubscription.setting = setting
            return (oldSubscription, false)
        } else {
            let subscriptionProperty = Subscription.Property(policyRaw: policy.rawValue)
            let subscription = Subscription.insert(
                into: managedObjectContext,
                property: subscriptionProperty,
                setting: setting
            )
            let alertProperty = SubscriptionAlerts.Property(policy: policy)
            subscription.alert = SubscriptionAlerts.insert(
                into: managedObjectContext,
                property: alertProperty,
                subscription: subscription
            )
                
            return (subscription, true)
        }
    }
    
}

extension APIService.CoreData {
    
    static func merge(
        subscription: Subscription,
        property: Subscription.Property,
        networkDate: Date
    ) {
        // TODO:
    }
    
}
