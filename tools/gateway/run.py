#!/usr/bin/env python3
"""Generate and run a local TLS Envoy gRPC-Web gateway, without Docker."""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import urllib.parse

def config(args):
    origin = urllib.parse.urlsplit(args.origin)
    if origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.path or origin.query or origin.fragment:
        raise ValueError('origin must be an HTTPS origin without a path or credentials')
    for name in ('certificate', 'private_key', 'backend_ca'):
        value = pathlib.Path(getattr(args, name)).resolve(strict=True)
        if not value.is_file():
            raise ValueError(f'{name} must be a file')
        setattr(args, name, str(value))
    for value in (args.port, args.backend_port):
        if not 1 <= value <= 65535:
            raise ValueError('port must be between 1 and 65535')
    if not args.backend_host or any(c in args.backend_host for c in '\r\n\x00/ '):
        raise ValueError('invalid backend host')
    filter = lambda name, type, **fields: {'name': name, 'typed_config': {'@type': type, **fields}}
    origin_match = {'name': 'origin', 'string_match': {'exact': args.origin}}
    http_filters = [
        filter('envoy.filters.http.rbac', 'type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC', rules={'action': 'ALLOW', 'policies': {'web_origin': {'permissions': [{'header': origin_match}], 'principals': [{'any': True}]}}}),
        filter('envoy.filters.http.grpc_web', 'type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb'),
        filter('envoy.filters.http.cors', 'type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors'),
        filter('envoy.filters.http.buffer', 'type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer', max_request_bytes=2*1024*1024),
        filter('envoy.filters.http.router', 'type.googleapis.com/envoy.extensions.filters.http.router.v3.Router'),
    ]
    cors = {'@type': 'type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy', 'allow_origin_string_match': [{'exact': args.origin}], 'allow_methods': 'POST, OPTIONS', 'allow_headers': 'authorization,content-type,x-grpc-web,x-user-agent,grpc-timeout', 'expose_headers': 'grpc-status,grpc-message,ffido-error-details-bin', 'max_age': '600'}
    manager = filter('envoy.filters.network.http_connection_manager', 'type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager', stat_prefix='ffido_web', codec_type='AUTO', max_request_headers_kb=8, stream_idle_timeout='15s', request_timeout='15s', route_config={'name': 'ffido', 'virtual_hosts': [{'name': 'ffido', 'domains': ['*'], 'typed_per_filter_config': {'envoy.filters.http.cors': cors}, 'routes': [{'match': {'prefix': '/ffido.v1.Ffido/'}, 'route': {'cluster': 'ffido_backend', 'timeout': '15s', 'max_stream_duration': {'max_stream_duration': '15s'}}}]}]}, http_filters=http_filters)
    downstream = {'name': 'envoy.transport_sockets.tls', 'typed_config': {'@type': 'type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext', 'common_tls_context': {'tls_params': {'tls_minimum_protocol_version': 'TLSv1_2'}, 'tls_certificates': [{'certificate_chain': {'filename': args.certificate}, 'private_key': {'filename': args.private_key}}]}}}
    upstream = {'name': 'envoy.transport_sockets.tls', 'typed_config': {'@type': 'type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext', 'sni': args.backend_host, 'common_tls_context': {'tls_params': {'tls_minimum_protocol_version': 'TLSv1_2'}, 'validation_context': {'trusted_ca': {'filename': args.backend_ca}, 'match_typed_subject_alt_names': [{'san_type': 'DNS', 'matcher': {'exact': args.backend_host}}]}}}}
    return {'overload_manager': {'resource_monitors': [{'name': 'envoy.resource_monitors.global_downstream_max_connections', 'typed_config': {'@type': 'type.googleapis.com/envoy.extensions.resource_monitors.downstream_connections.v3.DownstreamConnectionsConfig', 'max_active_downstream_connections': 256}}]}, 'static_resources': {'listeners': [{'name': 'ffido_web', 'enable_reuse_port': False, 'address': {'socket_address': {'address': '127.0.0.1', 'port_value': args.port}}, 'filter_chains': [{'transport_socket': downstream, 'filters': [manager]}]}], 'clusters': [{'name': 'ffido_backend', 'type': 'STRICT_DNS', 'dns_lookup_family': 'V4_ONLY', 'connect_timeout': '2s', 'load_assignment': {'cluster_name': 'ffido_backend', 'endpoints': [{'lb_endpoints': [{'endpoint': {'address': {'socket_address': {'address': args.backend_host, 'port_value': args.backend_port}}}}]}]}, 'typed_extension_protocol_options': {'envoy.extensions.upstreams.http.v3.HttpProtocolOptions': {'@type': 'type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions', 'explicit_http_config': {'http2_protocol_options': {}}}}, 'transport_socket': upstream}]}}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--envoy', default='envoy')
    parser.add_argument('--origin', required=True)
    parser.add_argument('--certificate', required=True)
    parser.add_argument('--private-key', required=True)
    parser.add_argument('--backend-ca', required=True)
    parser.add_argument('--backend-host', default='localhost')
    parser.add_argument('--backend-port', type=int, default=8080)
    parser.add_argument('--port', type=int, default=8443)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--validate', action='store_true')
    args = parser.parse_args()
    executable = shutil.which(args.envoy)
    if not executable:
        raise SystemExit('Required tool not found: Envoy')
    try:
        value = config(args)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, indent=2)+'\n')
    subprocess.run([executable, '--mode', 'validate', '-c', str(args.output)], check=True)
    if not args.validate:
        os.execv(executable, [executable, '-c', str(args.output), '--concurrency', '2'])

if __name__ == '__main__':
    main()
