import dbus

bus = dbus.SessionBus()
watcher = dbus.Interface(bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher'),
                         'org.freedesktop.DBus.Properties')
items = watcher.Get('org.kde.StatusNotifierWatcher', 'RegisteredStatusNotifierItems')
identities = []
for item in items:
    service, separator, path = str(item).partition('/')
    properties = dbus.Interface(bus.get_object(service, '/' + path if separator else '/StatusNotifierItem'),
                                'org.freedesktop.DBus.Properties')
    identities.append(str(properties.Get('org.kde.StatusNotifierItem', 'Id')))
assert any('1password' in identity.lower() for identity in identities), identities
print('1Password tray item registered')
