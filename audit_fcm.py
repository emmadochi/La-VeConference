keywords = ['/api/call/', 'notify_incoming_call', 'fcmToken', 'fcm_token',
            'messaging.send', 'MulticastMessage', 'send_in_app_notification',
            'call/notify', 'call/decline', 'call/accept', 'call/end',
            'call/missed', 'push_notification', 'notify_call', 'incoming_call',
            'call_room_id', 'callerId']

with open('main.py', encoding='utf-8') as f:
    for i, line in enumerate(f, 1):
        if any(k in line for k in keywords):
            print(f'{i}: {line.rstrip()}')
