#ifndef RUNNER_WIFI_TUNNEL_H_
#define RUNNER_WIFI_TUNNEL_H_

#include <optional>
#include <string>

struct WifiTunnel {
  int port;
  std::string token;
};

// Opens one loopback connection whose remote socket is pinned to the Wi-Fi
// interface. The returned port accepts one connection and expires after 10s.
std::optional<WifiTunnel> OpenWifiTunnel(const std::string& host, int port,
                                        const std::string& source_address,
                                        unsigned int interface_index);

#endif  // RUNNER_WIFI_TUNNEL_H_
