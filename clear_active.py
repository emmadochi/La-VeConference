import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("firebase-adminsdk.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

users_ref = db.collection('users').stream()
for doc in users_ref:
    db.collection('users').document(doc.id).update({'active_room': ''})
    print(f"Cleared active_room for {doc.id}")
