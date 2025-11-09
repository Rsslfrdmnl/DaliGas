import firebase_admin
from firebase_admin import credentials, firestore, auth

# Initialize with service account key
cred = credentials.Certificate('build/serviceAccountKey.json')
firebase_admin.initialize_app(cred)

db = firestore.client()

# Create Super Admin
try:
    user = auth.create_user(
        email='superadmin@gmail.com',
        password='admin123',  # Change this to a strong password
        display_name='Super Admin'
    )
    db.collection('admins').document(user.uid).set({
        'role': 'super',
        'email': user.email,
        'created_at': firestore.SERVER_TIMESTAMP
    })
    print(f'Created Super Admin with UID: {user.uid}')
except Exception as e:
    print(f'Error creating Super Admin: {e}')

# Create Sub Admin
try:
    user = auth.create_user(
        email='admin@gmail.com',
        password='admin123',  # Change this to a strong password
        display_name='Sub Admin'
    )
    db.collection('admins').document(user.uid).set({
        'role': 'admin',
        'email': user.email,
        'created_at': firestore.SERVER_TIMESTAMP
    })
    print(f'Created Sub Admin with UID: {user.uid}')
except Exception as e:
    print(f'Error creating Sub Admin: {e}')

# Optional: Clean up (delete the service account key after running)
print('Accounts created. Delete the service account key for security.')