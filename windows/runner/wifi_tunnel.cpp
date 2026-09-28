#include <winsock2.h>
#include <ws2tcpip.h>
#include <bcrypt.h>
#include <windns.h>

#include "wifi_tunnel.h"

#include <array>
#include <thread>
#include <vector>

namespace {

bool WaitForSocket(SOCKET socket, bool writable) {
  fd_set ready;
  FD_ZERO(&ready);
  FD_SET(socket, &ready);
  timeval timeout{10, 0};
  return select(0, writable ? nullptr : &ready, writable ? &ready : nullptr,
                nullptr, &timeout) == 1;
}

std::vector<sockaddr_in> ResolveOnWifi(const std::string& host, int port,
                                       unsigned int interface_index) {
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(static_cast<u_short>(port));
  if (InetPtonA(AF_INET, host.c_str(), &address.sin_addr) == 1) {
    return {address};
  }

  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         host.c_str(), -1, nullptr, 0);
  if (length <= 0) return {};
  std::wstring name(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, host.c_str(), -1,
                          name.data(), length) == 0) return {};

  DNS_QUERY_REQUEST request{};
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.QueryName = name.c_str();
  request.QueryType = DNS_TYPE_A;
  request.QueryOptions = DNS_QUERY_BYPASS_CACHE;
  request.InterfaceIndex = interface_index;
  DNS_QUERY_RESULT result{};
  result.Version = DNS_QUERY_RESULTS_VERSION1;
  const DNS_STATUS status = DnsQueryEx(&request, &result, nullptr);
  std::vector<sockaddr_in> addresses;
  if (status == ERROR_SUCCESS && result.QueryStatus == ERROR_SUCCESS) {
    for (auto* record = result.pQueryRecords; record; record = record->pNext) {
      if (record->wType != DNS_TYPE_A) continue;
      address.sin_addr.s_addr = htonl(record->Data.A.IpAddress);
      addresses.push_back(address);
    }
  }
  if (result.pQueryRecords) {
    DnsRecordListFree(result.pQueryRecords, DnsFreeRecordList);
  }
  return addresses;
}

SOCKET ConnectOnWifi(const std::string& host, int port,
                     const std::string& source_address,
                     unsigned int interface_index) {
  const auto addresses = ResolveOnWifi(host, port, interface_index);

  SOCKET remote = INVALID_SOCKET;
  for (const auto& target : addresses) {
    remote = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (remote == INVALID_SOCKET) break;
    const DWORD outgoing_interface = htonl(interface_index);
    sockaddr_in source{};
    source.sin_family = AF_INET;
    source.sin_port = 0;
    if (InetPtonA(AF_INET, source_address.c_str(), &source.sin_addr) != 1 ||
        setsockopt(remote, IPPROTO_IP, IP_UNICAST_IF,
                   reinterpret_cast<const char*>(&outgoing_interface),
                   sizeof(outgoing_interface)) == SOCKET_ERROR ||
        bind(remote, reinterpret_cast<sockaddr*>(&source), sizeof(source)) ==
            SOCKET_ERROR) {
      closesocket(remote);
      remote = INVALID_SOCKET;
      break;
    }

    u_long nonblocking = 1;
    ioctlsocket(remote, FIONBIO, &nonblocking);
    const int connected = connect(
        remote, reinterpret_cast<const sockaddr*>(&target), sizeof(target));
    bool ready = connected == 0;
    if (!ready && WSAGetLastError() == WSAEWOULDBLOCK &&
        WaitForSocket(remote, true)) {
      int error = 0;
      int length = sizeof(error);
      ready = getsockopt(remote, SOL_SOCKET, SO_ERROR,
                         reinterpret_cast<char*>(&error), &length) == 0 &&
              error == 0;
    }
    nonblocking = 0;
    ioctlsocket(remote, FIONBIO, &nonblocking);
    if (ready) break;
    closesocket(remote);
    remote = INVALID_SOCKET;
  }
  return remote;
}

bool Forward(SOCKET from, SOCKET to) {
  std::array<char, 8192> bytes{};
  const int read = recv(from, bytes.data(), static_cast<int>(bytes.size()), 0);
  if (read <= 0) return false;
  for (int sent = 0; sent < read;) {
    const int count = send(to, bytes.data() + sent, read - sent, 0);
    if (count <= 0) return false;
    sent += count;
  }
  return true;
}

bool ReadToken(SOCKET socket, const std::string& token) {
  std::array<char, 32> received{};
  size_t offset = 0;
  while (offset < token.size()) {
    if (!WaitForSocket(socket, false)) return false;
    const int count = recv(socket, received.data() + offset,
                           static_cast<int>(token.size() - offset), 0);
    if (count <= 0) return false;
    offset += count;
  }
  return std::string(received.data(), token.size()) == token;
}

void ServeTunnel(SOCKET listener, std::string host, int port,
                 std::string source_address, unsigned int interface_index,
                 std::string token) {
  if (!WaitForSocket(listener, false)) {
    closesocket(listener);
    WSACleanup();
    return;
  }
  SOCKET local = accept(listener, nullptr, nullptr);
  closesocket(listener);
  if (local == INVALID_SOCKET) {
    WSACleanup();
    return;
  }
  if (!ReadToken(local, token)) {
    closesocket(local);
    WSACleanup();
    return;
  }
  SOCKET remote = ConnectOnWifi(host, port, source_address, interface_index);
  if (remote != INVALID_SOCKET) {
    while (true) {
      fd_set ready;
      FD_ZERO(&ready);
      FD_SET(local, &ready);
      FD_SET(remote, &ready);
      if (select(0, &ready, nullptr, nullptr, nullptr) <= 0) break;
      if (FD_ISSET(local, &ready) && !Forward(local, remote)) break;
      if (FD_ISSET(remote, &ready) && !Forward(remote, local)) break;
    }
    closesocket(remote);
  }
  closesocket(local);
  WSACleanup();
}

}  // namespace

std::optional<WifiTunnel> OpenWifiTunnel(const std::string& host, int port,
                                        const std::string& source_address,
                                        unsigned int interface_index) {
  if (host.empty() || port <= 0 || port > 65535 || interface_index == 0)
    return std::nullopt;

  std::array<unsigned char, 16> random{};
  if (BCryptGenRandom(nullptr, random.data(),
                      static_cast<ULONG>(random.size()),
                      BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
    return std::nullopt;
  }
  constexpr char hex[] = "0123456789abcdef";
  std::string token;
  token.reserve(random.size() * 2);
  for (const auto byte : random) {
    token += hex[byte >> 4];
    token += hex[byte & 15];
  }

  WSADATA wsa{};
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return std::nullopt;
  SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listener == INVALID_SOCKET) {
    WSACleanup();
    return std::nullopt;
  }
  sockaddr_in local{};
  local.sin_family = AF_INET;
  local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  local.sin_port = 0;
  int length = sizeof(local);
  const BOOL exclusive = TRUE;
  if (setsockopt(listener, SOL_SOCKET, SO_EXCLUSIVEADDRUSE,
                 reinterpret_cast<const char*>(&exclusive), sizeof(exclusive)) ==
          SOCKET_ERROR ||
      bind(listener, reinterpret_cast<sockaddr*>(&local), length) ==
          SOCKET_ERROR ||
      listen(listener, 1) == SOCKET_ERROR ||
      getsockname(listener, reinterpret_cast<sockaddr*>(&local), &length) ==
          SOCKET_ERROR) {
    closesocket(listener);
    WSACleanup();
    return std::nullopt;
  }
  const int local_port = ntohs(local.sin_port);
  try {
    std::thread(ServeTunnel, listener, host, port, source_address,
                interface_index, token)
        .detach();
  } catch (...) {
    closesocket(listener);
    WSACleanup();
    return std::nullopt;
  }
  return WifiTunnel{local_port, token};
}
