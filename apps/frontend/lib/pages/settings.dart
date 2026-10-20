import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/session_store.dart';
import '../main.dart' show apiClient;

class SettingsWidget extends StatefulWidget {
  const SettingsWidget({
    super.key,
    this.client,
    this.preferences,
    this.store,
    this.initialMessage = '',
  });
  final ApiClient? client;
  final SharedPreferences? preferences;
  final SessionStore? store;
  final String initialMessage;
  @override
  State<SettingsWidget> createState() => _SettingsWidgetState();
}

class _SettingsWidgetState extends State<SettingsWidget> {
  late final TextEditingController _endpoint;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _message = '';
  Map<String, List<String>> _errors = {};
  ApiClient get _client => widget.client ?? apiClient;
  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(text: _client.endpoint.toString());
    _message = widget.initialMessage;
    _loadFields();
  }

  Future<void> _loadFields() async {
    final prefs = widget.preferences ?? await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name.text =
          _client.session?.profile.name ??
          prefs.getString('ffido_name_v1') ??
          '';
      _address.text =
          _client.session?.profile.address ??
          prefs.getString('ffido_address_v1') ??
          '';
    });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _name.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save({bool logout = false}) async {
    setState(() {
      _busy = true;
      _message = '';
      _errors = {};
    });
    try {
      final prefs = widget.preferences ?? await SharedPreferences.getInstance();
      final manager = SessionManager(
        _client,
        prefs,
        store: widget.store ?? const SecureSessionStore(),
      );
      final message = logout
          ? await manager.logout()
          : await manager.connect(
              endpoint: _endpoint.text,
              name: _name.text,
              address: _address.text,
              password: _password.text,
            );
      if (!mounted) return;
      _password.clear();
      setState(() {
        _message = message;
        if (_client.session != null) {
          _name.text = _client.session!.profile.name;
          _address.text = _client.session!.profile.address;
        }
      });
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() {
          _errors = error.fieldErrors;
          _message = 'Проверьте поля подключения';
        });
      }
    } on UnauthorizedException {
      if (mounted) {
        setState(
          () => _message =
              'Неверный FTN-адрес или пароль. Проверьте данные подключения.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Не удалось подключиться. Проверьте адрес сервера и доступность сети.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: Key(key),
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[key]?.join('\n'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключение к FFIDO')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _field('name', 'Имя', _name),
        _field('address', 'FTN-адрес', _address),
        _field('password', 'Пароль', _password, secret: true),
        _field('endpoint', 'Адрес сервера', _endpoint),
        const Text(
          'Используйте FTN-адрес и пароль, настроенные у вашего сисопа. Адрес сервера: https://fido.example.org',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _save(),
          child: const Text('Подключиться'),
        ),
        if (_client.hasToken) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _save(logout: true),
            child: const Text('Выйти'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (_) => false),
            child: const Text('Открыть конференции'),
          ),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_message.isNotEmpty)
          Text(_message, key: const Key('connection-message')),
      ],
    ),
  );
}
