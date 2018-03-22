/*
 *  Copyright (c) 2011-2018, Zingaya, Inc. All rights reserved.
 */

import UIKit
import VoxImplant

enum CallNotificationCategory: String {
    case video = "kVideoCallNotificationCategory"
    case audio = "kAudioCallNotificationCategory"
}

enum CallNotificationAction: String {
    case reject = "kRejectCallNotificationAction"
    case answerVideo = "kAnswerVideoCallNotificationAction"
    case answerAudio = "kAnswerAudioCallNotificationAction"
}

class NotificationCallManager: CallManager {
    let kCallNotificationIdentifier = "kCallNotificationIdentifier"

    private(set) var activeCall: CallDescriptor? = nil
    private(set) var registeredCalls: [UUID: CallDescriptor]! = [:]

    var pendingCall: CallDescriptor? {
        get {
            for (_, descriptor) in registeredCalls {
                if !descriptor.started {
                    return descriptor
                }
            }
            return nil
        }
    }

    func call(uuid: UUID!) -> CallDescriptor? {
        return self.registeredCalls[uuid]
    }

    func call(call: VICall!) -> CallDescriptor? {
        for (_, descriptor) in self.registeredCalls {
            if descriptor.call == call {
                return descriptor
            }
        }
        return nil
    }

    func registerCall(_ descriptor: CallDescriptor!) {
        self.registeredCalls[descriptor.uuid] = descriptor

        if (descriptor.incoming) {
            notifyIncomingCall(descriptor)
        } else {
            AppDelegate.instance().voxImplant!.startCall(call: descriptor)
        }
    }

    func startCall(_ descriptor: CallDescriptor!) {
        descriptor.started = true
        self.activeCall = descriptor
    }

    func endCall(_ descriptor: CallDescriptor!) {
        if self.activeCall?.uuid == descriptor.uuid {
            self.activeCall = nil
        }
        self.registeredCalls.removeValue(forKey: descriptor.uuid)
    }

    func notifyIncomingCall(_ descriptor: CallDescriptor!) {
        if #available(iOS 10.0, *) {
            notifyIncomingCallCurrent(descriptor)
        } else {
            notifyIncomingCallLegacy(descriptor)
        }
    }

    func registerCallManager() {
        Log.i("Registering Notification Call Manager")
        if #available(iOS 10.0, *) {
            registerCallManagerCurrent()
        } else {
            registerCallManagerLegacy()
        }
    }
}

@available(iOS 8.0, *)
extension NotificationCallManager {
    func registerCallManagerLegacy() {
        let notificationTypes: UIUserNotificationType = [
            UIUserNotificationType.alert,
            UIUserNotificationType.sound,
            UIUserNotificationType.badge
        ]

        let rejectCall = UIMutableUserNotificationAction()
        rejectCall.identifier = CallNotificationAction.reject.rawValue
        rejectCall.title = "Reject"
        rejectCall.activationMode = .background
        rejectCall.isDestructive = true
        rejectCall.isAuthenticationRequired = false

        let answerVideo = UIMutableUserNotificationAction()
        answerVideo.identifier = CallNotificationAction.answerVideo.rawValue
        answerVideo.title = "Answer"
        answerVideo.activationMode = .foreground
        answerVideo.isAuthenticationRequired = true

        let answerAudio = UIMutableUserNotificationAction()
        answerAudio.identifier = CallNotificationAction.answerAudio.rawValue
        answerAudio.title = "Answer"
        answerAudio.activationMode = .foreground
        answerAudio.isAuthenticationRequired = true

        let audioActions: [UIUserNotificationAction] = [rejectCall, answerAudio]
        let videoActionsMinimal: [UIUserNotificationAction] = [rejectCall, answerVideo]
        let videoActions: [UIUserNotificationAction] = [rejectCall, answerAudio, answerVideo]

        let audioCallCategory = UIMutableUserNotificationCategory()
        audioCallCategory.identifier = CallNotificationCategory.audio.rawValue
        audioCallCategory.setActions(audioActions, for: .default)
        audioCallCategory.setActions(audioActions, for: .minimal)

        let videoCallCategory = UIMutableUserNotificationCategory()
        videoCallCategory.identifier = CallNotificationCategory.video.rawValue
        videoCallCategory.setActions(videoActions, for: .default)
        videoCallCategory.setActions(videoActionsMinimal, for: .minimal)

        let notificationCategories: Set<UIUserNotificationCategory> = [audioCallCategory, videoCallCategory]

        let newNotificationSettings = UIUserNotificationSettings(types: notificationTypes, categories: notificationCategories)
        UIApplication.shared.registerUserNotificationSettings(newNotificationSettings)
    }

    func notifyIncomingCallLegacy(_ descriptor: CallDescriptor!) {
        let notification = UILocalNotification()
        notification.fireDate = NSDate(timeIntervalSinceNow: 0) as Date
        if #available(iOS 8.2, *) {
            notification.alertTitle = "Voximplant"
        }
        notification.alertBody = String(format: "Incoming %@ call from %@", descriptor.withVideo ? "video" : "audio", descriptor.call!.endpoints!.first!.userDisplayName)
        notification.soundName = "ringtone.aiff"
        notification.category = descriptor.withVideo ? CallNotificationCategory.video.rawValue : CallNotificationCategory.audio.rawValue
        notification.userInfo = ["uuid": descriptor.uuid.uuidString]
        UIApplication.shared.scheduleLocalNotification(notification)
    }
}

import UserNotifications

@available(iOS 10.0, *)
extension NotificationCallManager {
    func registerCallManagerCurrent() {
        let options: UNAuthorizationOptions = [
            UNAuthorizationOptions.alert,
            UNAuthorizationOptions.sound,
            UNAuthorizationOptions.badge
        ]

        let rejectCall = UNNotificationAction(identifier: CallNotificationAction.reject.rawValue, title: "Reject", options: [.destructive])
        let answerAudio = UNNotificationAction(identifier: CallNotificationAction.answerAudio.rawValue, title: "Answer", options: [.foreground])
        let answerVideo = UNNotificationAction(identifier: CallNotificationAction.answerVideo.rawValue, title: "Answer", options: [.foreground])

        let audioCategory = UNNotificationCategory(identifier: CallNotificationCategory.audio.rawValue, actions: [rejectCall, answerAudio], intentIdentifiers: [], options: [])
        let videoCategory = UNNotificationCategory(identifier: CallNotificationCategory.video.rawValue, actions: [rejectCall, answerVideo], intentIdentifiers: [], options: [])

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: options) { granted, error in
            guard granted else {
                UIHelper.ShowError(error: error?.localizedDescription, action: nil)
                return
            }
            center.setNotificationCategories([audioCategory, videoCategory])

            AppDelegate.instance().voxImplant!.registerForPushNotifications()
        }
    }

    func notifyIncomingCallCurrent(_ descriptor: CallDescriptor!) {
        let content = UNMutableNotificationContent()
        content.title = "Voximplant"
        content.subtitle = String(format: "Incoming %@ call", descriptor.withVideo ? "video" : "audio")
        content.body = String(format: "from %@", descriptor.call!.endpoints!.first!.userDisplayName)
        content.categoryIdentifier = descriptor.withVideo ? CallNotificationCategory.video.rawValue : CallNotificationCategory.audio.rawValue
        content.sound = UNNotificationSound(named: "ringtone.aiff")
        content.userInfo = ["uuid": descriptor.uuid.uuidString]

        let request = UNNotificationRequest(identifier: kCallNotificationIdentifier, content: content, trigger: nil)

        let center = UNUserNotificationCenter.current()
        center.add(request) { error in
            guard error == nil else {
                UIHelper.ShowError(error: error!.localizedDescription, action: nil)
                return
            }
        }
    }
}