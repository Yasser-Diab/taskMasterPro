#include <windows.h>  // <-- This must be the first Windows header
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Xml.Dom.h>

#include "ffi_api.h"
#include "plugin.hpp"
#include "utils.hpp"

using winrt::Windows::Data::Xml::Dom::XmlDocument;

bool hasPackageIdentity() {
  if (!IsWindows8OrGreater()) return false;
  uint32_t length = 0;
  int error = GetCurrentPackageFullName(&length, nullptr);
  return error != APPMODEL_ERROR_NO_PACKAGE;
}

NativePlugin* createPlugin() { return new NativePlugin(); }

void disposePlugin(NativePlugin* plugin) { delete plugin; }

bool init(
  NativePlugin* plugin, char* appName, char* aumId, char* guid, char* iconPath,
  NativeNotificationCallback callback
) {
  string icon;
  if (iconPath != nullptr) icon = string(iconPath);
  const auto didRegister = plugin->registerApp(aumId, appName, guid, icon, callback);
  if (!didRegister) return false;
  plugin->hasIdentity = hasPackageIdentity();
  plugin->aumid = winrt::to_hstring(aumId);
  plugin->notifier = plugin->hasIdentity
    ? ToastNotificationManager::CreateToastNotifier()
    : ToastNotificationManager::CreateToastNotifier(plugin->aumid);
  plugin->history = ToastNotificationManager::History();
  plugin->isReady = true;
  return true;
}

bool isValidXml(char* xml) {
  XmlDocument doc = XmlDocument();
  try {
    doc.LoadXml(winrt::to_hstring(xml));
    return true;
  } catch (winrt::hresult_error error) {
    return false;
  }
}

bool showNotification(NativePlugin* plugin, int id, char* xml, NativeStringMap bindings) {
  if (!plugin->isReady) return false;
  try {
    XmlDocument doc;
    doc.LoadXml(winrt::to_hstring(xml));
    ToastNotification notification(doc);
    const auto data = dataFromMap(bindings);
    notification.Tag(winrt::to_hstring(id));
    notification.Data(data);
    plugin->notifier.value().Show(notification);
    return true;
  } catch (const winrt::hresult_error&) {
    // Native WinRT exceptions must never escape across the Dart FFI boundary.
    return false;
  } catch (...) {
    return false;
  }
}

int32_t scheduleNotification(NativePlugin* plugin, int id, char* xml, int time) {
  if (!plugin->isReady) return E_UNEXPECTED;
  try {
    XmlDocument doc;
    doc.LoadXml(winrt::to_hstring(xml));
    ScheduledToastNotification notification(
      doc, winrt::clock::from_time_t(time)
    );
    const auto tag = winrt::to_hstring(id);
    notification.Tag(tag);

    // AddToSchedule appends even when another toast has the same tag. Replace
    // matching entries first so repeated app resume/realtime synchronization
    // cannot consume the Windows scheduled-toast quota.
    const auto scheduled =
      plugin->notifier.value().GetScheduledToastNotifications();
    for (const auto existing : scheduled) {
      if (existing.Tag() == tag) {
        plugin->notifier.value().RemoveFromSchedule(existing);
      }
    }

    plugin->notifier.value().AddToSchedule(notification);
    return S_OK;
  } catch (const winrt::hresult_error& error) {
    // In particular, AddToSchedule throws 0x80070718 when the schedule is in
    // the past or Windows' toast quota is exhausted. Returning the HRESULT
    // keeps the host process alive and lets Dart diagnose and retry safely.
    return error.code().value;
  } catch (...) {
    return E_FAIL;
  }
}

NativeUpdateResult updateNotification(NativePlugin* plugin, int id, NativeStringMap bindings) {
  if (!plugin->isReady) return NativeUpdateResult::failed;
  const auto tag = winrt::to_hstring(id);
  const auto data = dataFromMap(bindings);
  const auto result = plugin->notifier.value().Update(data, tag);
  return (NativeUpdateResult) result;
}

void cancelAll(NativePlugin* plugin) {
  if (!plugin->isReady) return;
  try {
    if (plugin->hasIdentity) {
      plugin->history.value().Clear();
    } else {
      plugin->history.value().Clear(plugin->aumid);
    }
  } catch (const winrt::hresult_error&) {
    // Visible-history cleanup is independent from scheduled-toast cleanup.
  } catch (...) {
  }
  try {
    const auto scheduled =
      plugin->notifier.value().GetScheduledToastNotifications();
    for (const auto notification : scheduled) {
      try {
        plugin->notifier.value().RemoveFromSchedule(notification);
      } catch (const winrt::hresult_error&) {
        // Continue repairing the rest of a partially corrupt or over-quota
        // schedule.
      } catch (...) {
      }
    }
  } catch (const winrt::hresult_error&) {
    // Best-effort cleanup: a Windows notification failure must not crash the
    // application while repairing an old schedule.
  } catch (...) {
  }
}

void cancelNotification(NativePlugin* plugin, int id) {
  if (!plugin->isReady) return;
  try {
    const auto tag = winrt::to_hstring(id);
    if (plugin->hasIdentity) plugin->history.value().Remove(tag);
    const auto scheduled =
      plugin->notifier.value().GetScheduledToastNotifications();
    for (const auto notification : scheduled) {
      if (notification.Tag() == tag) {
        plugin->notifier.value().RemoveFromSchedule(notification);
      }
    }
  } catch (const winrt::hresult_error&) {
    // Best-effort cleanup; do not let WinRT exceptions cross FFI.
  } catch (...) {
  }
}

NativeNotificationDetails* getActiveNotifications(NativePlugin* plugin, int* size) {
  // TODO: Get more details here
  if (!plugin->isReady || !plugin->hasIdentity) {
    *size = 0;
    return nullptr;
  }
  const auto active = plugin->history.value().GetHistory();
  *size = active.Size();
  const auto result = new NativeNotificationDetails[*size];
  int index = 0;
  for (const auto notification : active) {
    const auto tag = notification.Tag();
    const auto tagStr = winrt::to_string(tag);
    const auto tagInt = std::stoi(tagStr);
    result[index].id = tagInt;
    const auto launch =
      notification.Content().DocumentElement().GetAttribute(L"launch");
    result[index].payload = toNativeString(winrt::to_string(launch));
    index++;
  }
  return result;
}

NativeNotificationDetails* getPendingNotifications(NativePlugin* plugin, int* size) {
  // TODO: Get more details here
  if (!plugin->isReady) {
    *size = 0;
    return nullptr;
  }
  try {
    const auto pending =
      plugin->notifier.value().GetScheduledToastNotifications();
    *size = pending.Size();
    const auto result = new NativeNotificationDetails[*size];
    int index = 0;
    for (const auto notification : pending) {
      const auto tag = notification.Tag();
      const auto tagStr = winrt::to_string(tag);
      const auto tagInt = std::stoi(tagStr);
      result[index].id = tagInt;
      const auto launch =
        notification.Content().DocumentElement().GetAttribute(L"launch");
      result[index].payload = toNativeString(winrt::to_string(launch));
      index++;
    }
    return result;
  } catch (const winrt::hresult_error&) {
    *size = 0;
    return nullptr;
  } catch (...) {
    *size = 0;
    return nullptr;
  }
}

void freeDetailsArray(NativeNotificationDetails* ptr, int size) {
  if (ptr == nullptr) return;
  for (int index = 0; index < size; index++) {
    if (ptr[index].payload != nullptr) delete[] ptr[index].payload;
  }
  delete[] ptr;
}

void freeLaunchDetails(NativeLaunchDetails details) {
  if (details.payload != nullptr) delete[] details.payload;
  for (int index = 0; index < details.data.size; index++) {
    const auto pair = details.data.entries[index];
    delete pair.key;
    delete pair.value;
  }
  if (details.data.entries != nullptr) delete[] details.data.entries;
}
