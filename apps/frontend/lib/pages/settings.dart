import '../api/message_footer.dart';
import '../updates/update_controller.dart';
import '../updates/update_ui.dart';

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
    this.footerSettings,
  });
  final ApiClient? client;
  final SharedPreferences? preferences;
  final SessionStore? store;
  final String initialMessage;
  final MessageFooterSettings? footerSettings;
  @override
  State<SettingsWidget> createState() => _SettingsWidgetState();
}

class _SettingsWidgetState extends State<SettingsWidget> {
  late final TextEditingController _endpoint;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _tagline = TextEditingController();
  final _origin = TextEditingController();
  MessageFooterSettings? _footer;
  String _savedTagline = '', _savedOrigin = '';
  bool _busy = false;
  bool _passwordAutofilled = false;
  String _savedPassword = '';
  String _message = '';
  String _savedName = '', _savedAddress = '', _savedEndpoint = '';
  Map<String, List<String>> _errors = {};
  ApiClient get _client => widget.client ?? apiClient;
  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(text: _client.endpoint.toString());
    _message = widget.initialMessage;
    _savedEndpoint = _endpoint.text;
    appUpdates.guardExit(
      this,
      () =>
          !_busy &&
          _password.text == _savedPassword &&
          _endpoint.text == _savedEndpoint &&
          _name.text == _savedName &&
          _address.text == _savedAddress &&
          _tagline.text == _savedTagline &&
          _origin.text == _savedOrigin,
    );
    _loadFields();
    _loadFooter();
  }

  Future<void> _loadFooter() async {
    final footer =
        widget.footerSettings ??
        await MessageFooterSettings.load(widget.preferences);
    if (!mounted) return;
    setState(() {
      _footer = footer;
      _tagline.text = _savedTagline = footer.tagline;
      _origin.text = _savedOrigin = footer.origin;
    });
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
      _savedName = _name.text;
      _savedAddress = _address.text;
    });
    final endpoint = _endpoint.text;
    final address = _address.text;
    try {
      final password = await SessionManager(
        _client,
        prefs,
        store: widget.store ?? const SecureSessionStore(),
      ).savedPassword(endpoint, address);
      if (!mounted ||
          _busy ||
          _endpoint.text != endpoint ||
          _address.text != address ||
          _password.text.isNotEmpty ||
          password == null) {
        return;
      }
      setState(() {
        _password.text = password;
        _savedPassword = password;
        _passwordAutofilled = true;
      });
    } catch (_) {
      // Keychain may be unavailable; keep manual login usable without a plaintext fallback.
    }
  }

  @override
  void dispose() {
    appUpdates.removeExitGuard(this);
    _endpoint.dispose();
    _name.dispose();
    _address.dispose();
    _password.dispose();
    _tagline.dispose();
    _origin.dispose();
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
      if (logout) _password.clear();
      _savedPassword = _password.text;
      _passwordAutofilled = !logout && _password.text.isNotEmpty;
      setState(() {
        _message = message;
        if (_client.session != null) {
          _name.text = _client.session!.profile.name;
          _address.text = _client.session!.profile.address;
        }
        _savedName = _name.text;
        _savedAddress = _address.text;
        _savedEndpoint = _endpoint.text;
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
          () => _message = 'Не удалось подключиться. Проверьте адрес сервера и доступность сети.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveFooter({bool reset = false}) async {
    final footer = _footer;
    if (footer == null || _busy) return;
    setState(() {
      _busy = true;
      _errors = {};
      _message = '';
    });
    try {
      if (reset) {
        await footer.reset();
      } else {
        await footer.save(_tagline.text, _origin.text);
      }
      if (!mounted) return;
      setState(() {
        _tagline.text = _savedTagline = footer.tagline;
        _origin.text = _savedOrigin = footer.origin;
        _message = 'Оформление сохранено';
      });
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() {
          _errors = error.fieldErrors;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось сохранить оформление');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    bool secret = false,
    bool loading = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: Key(key),
      controller: controller,
      enabled: !_busy && !loading,
      obscureText: secret,
      onChanged: key == 'endpoint' || key == 'address'
          ? (_) {
              if (_passwordAutofilled) {
                _password.clear();
                _savedPassword = '';
                _passwordAutofilled = false;
              }
            }
          : key == 'password'
          ? (_) {
              _passwordAutofilled = false;
            }
          : null,
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
    appBar: AppBar(
      title: const Text('Подключение к FFIDO'),
      actions: const [UpdateButton()],
    ),
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
                : () =>
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (_) => false),
            child: const Text('Открыть конференции'),
          ),
        ],
        const Divider(),
        const Text('Оформление исходящих сообщений'),
        _field(
          'tagline',
          'Tagline (после ---)',
          _tagline,
          loading: _footer == null,
        ),
        _field('origin', 'Origin', _origin, loading: _footer == null),
        const Text(
          'FTN-адрес в Origin добавляет сервер. Оформление применяется только к эхам.',
        ),
        if (!_client.supportsMessageFooter)
          const Text(
            'Пользовательское оформление требует обновлённого сервера FFIDO.',
          ),
        FilledButton(
          onPressed: _busy || _footer == null ? null : () => _saveFooter(),
          child: const Text('Сохранить оформление'),
        ),
        TextButton(
          onPressed: _busy || _footer == null
              ? null
              : () => _saveFooter(reset: true),
          child: const Text('Сбросить оформление'),
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_message.isNotEmpty)
          Text(_message, key: const Key('connection-message')),
      ],
    ),
  );
}
