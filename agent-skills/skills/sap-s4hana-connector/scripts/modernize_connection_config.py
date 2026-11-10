#!/usr/bin/env python3
"""Bring a freshly generated + clientSanitations'd S/4HANA package up to the ballerinax/sap 1.4.0 shape.

This replays what the reference repos did by hand after generation (for example
module-ballerinax-sap.s4hana.qm commit 0319169):
  * client.bal: the init maps ConnectionConfig straight onto sap:ConnectionConfig
    (no http:ClientConfiguration, no ensureType block, no httpEp temp).
  * types.bal: ConnectionConfig gets the modern field list (http:ClientHttp1Settings,
    followRedirects, cookieConfig, socketConfig, laxDataBinding, {} defaults) and the
    local ProxyConfig / ClientHttp1Settings records are removed.

Idempotent: running it on an already modern package changes nothing.

Usage: modernize_connection_config.py <package-dir>
"""
import re
import sys
from pathlib import Path

FIELDS = """    # The HTTP version understood by the client
    http:HttpVersion httpVersion = http:HTTP_2_0;
    # Configurations related to HTTP/1.x protocol
    http:ClientHttp1Settings http1Settings = {};
    # Configurations related to HTTP/2 protocol
    http:ClientHttp2Settings http2Settings = {};
    # The maximum time to wait (in seconds) for a response before closing the connection
    decimal timeout = 60;
    # The choice of setting `forwarded`/`x-forwarded` header
    string forwarded = "disable";
    # Configurations associated with Redirection
    http:FollowRedirects followRedirects?;
    # Configurations associated with request pooling
    http:PoolConfiguration poolConfig?;
    # HTTP caching related configurations
    http:CacheConfig cache = {};
    # Specifies the way of handling compression (`accept-encoding`) header
    http:Compression compression = http:COMPRESSION_AUTO;
    # Configurations associated with the behaviour of the Circuit Breaker
    http:CircuitBreakerConfig circuitBreaker?;
    # Configurations associated with retrying
    http:RetryConfig retryConfig?;
    # Configurations associated with cookies
    http:CookieConfig cookieConfig?;
    # Configurations associated with inbound response size limits
    http:ResponseLimitConfigs responseLimits = {};
    # SSL/TLS-related options
    http:ClientSecureSocket secureSocket?;
    # Proxy server related options
    http:ProxyConfig proxy?;
    # Provides settings related to client socket configuration
    http:ClientSocketConfig socketConfig = {};
    # Enables the inbound payload validation functionality which provided by the constraint package. Enabled by default
    boolean validation = true;
    # Enables relaxed data binding on the client side. When enabled, `nil` values are treated as optional,
    # and absent fields are handled as `nilable` types. Enabled by default.
    boolean laxDataBinding = true;
"""

INIT = ("sap:ConnectionConfig httpClientConfig = {auth: config.auth, httpVersion: config.httpVersion, "
        "http1Settings: config.http1Settings, http2Settings: config.http2Settings, timeout: config.timeout, "
        "forwarded: config.forwarded, followRedirects: config.followRedirects, poolConfig: config.poolConfig, "
        "cache: config.cache, compression: config.compression, circuitBreaker: config.circuitBreaker, "
        "retryConfig: config.retryConfig, cookieConfig: config.cookieConfig, responseLimits: config.responseLimits, "
        "secureSocket: config.secureSocket, proxy: config.proxy, socketConfig: config.socketConfig, "
        "validation: config.validation, laxDataBinding: config.laxDataBinding};")


def fix_types(text: str) -> str:
    # Replace every field after `auth` in ConnectionConfig with the modern list.
    text = re.sub(r"(public type ConnectionConfig record \{\|\n    # Configurations related to client authentication\n    [^\n]*auth;\n)(.*?)(\|\};)",
                  lambda m: m.group(1) + FIELDS + m.group(3), text, count=1, flags=re.S)
    # Drop the local helper records the old generator emitted (doc comment + record).
    for name in ("ProxyConfig", "ClientHttp1Settings"):
        text = re.sub(r"(?:#[^\n]*\n)*public type " + name + r" record \{\|.*?\|\};\n", "", text, count=1, flags=re.S)
    return text


def fix_client(text: str) -> str:
    text = re.sub(r"http:ClientConfiguration httpClientConfig = \{.*?\n        sap:Client httpEp = check new \(serviceUrl, httpClientConfig\);\n"
                  r"        self\.clientEp = httpEp;\n        return;\n",
                  INIT + "\n        self.clientEp = check new (serviceUrl, httpClientConfig);\n", text, count=1, flags=re.S)
    # Newer generators already emit the modern field list; only the type name differs.
    text = text.replace("http:ClientConfiguration httpClientConfig", "sap:ConnectionConfig httpClientConfig")
    return text


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    pkg = Path(sys.argv[1])
    for name, fix in (("types.bal", fix_types), ("client.bal", fix_client)):
        path = pkg / name
        before = path.read_text()
        after = fix(before)
        path.write_text(after)
        print(f"{name}: {'updated' if after != before else 'unchanged'}")
    client = (pkg / "client.bal").read_text()
    if "http:ClientConfiguration" in client or "ensureType(ClientHttp1Settings)" in client:
        print("ERROR: client.bal still has the old init; inspect it by hand", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
