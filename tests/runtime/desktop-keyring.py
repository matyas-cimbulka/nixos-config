import dbus

# Keep one Secret Service connection and session for the collection query.
bus = dbus.SessionBus()
service = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets")
dbus.Interface(service, "org.freedesktop.Secret.Service").OpenSession("plain", dbus.String("", variant_level=1))
collection = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets/collection/login")
locked = dbus.Interface(collection, "org.freedesktop.DBus.Properties").Get("org.freedesktop.Secret.Collection", "Locked")
assert not locked, "Login keyring must unlock through the graphical PAM login"
