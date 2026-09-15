import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

void main() {
  runApp(const TradingSignalApp());
}

class TradingSignalApp extends StatelessWidget {
  const TradingSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Signal Bot',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F8CFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const TradingAnalyzerPage(),
    );
  }
}

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });
}

class SignalResult {
  final String action;
  final String display;
  final String arrow;
  final int score;
  final int maxScore;
  final String strength;
  final String reason;
  final String trend;
  final String momentum;
  final String priceAction;
  final double rsi;
  final double ema20;
  final double ema50;
  final double macd;
  final double macdSignal;
  final double adx;
  final Candle candle;

  const SignalResult({
    required this.action,
    required this.display,
    required this.arrow,
    required this.score,
    required this.maxScore,
    required this.strength,
    required this.reason,
    required this.trend,
    required this.momentum,
    required this.priceAction,
    required this.rsi,
    required this.ema20,
    required this.ema50,
    required this.macd,
    required this.macdSignal,
    required this.adx,
    required this.candle,
  });
}

class BiquoteService {
  static const String baseUrl = 'https://biquote.io/api';
  static const String hubUrl = 'https://biquote.io/hubs/tick';

  static String normalizeSymbol(String symbol) {
    return symbol.replaceAll('/', '').toUpperCase();
  }

  static Future<List<Candle>> getCandles(
    String symbol, {
    String interval = '1m',
    int limit = 200,
  }) async {
    final normalized = normalizeSymbol(symbol);

    final url = Uri.parse(
      '$baseUrl/$normalized/ohlc'
      '?interval=$interval&limit=$limit',
    );

    final response = await http.get(
      url,
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Biquote HTTP ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'Biquote devolvió una respuesta JSON inválida.',
      );
    }

    List<dynamic> raw = const [];

    /*
      Biquote devuelve:

      {
        "symbol": "EURUSD",
        "interval": "1m",
        "bars": [
          {
            "openTime": "...",
            "open": ...,
            "high": ...,
            "low": ...,
            "close": ...,
            "volume": ...,
            "tickVolume": ...,
            "isOpen": false
          }
        ]
      }

      También dejamos soporte para "data", "results"
      o una lista directa por compatibilidad.
    */

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      final bars = map['bars'];
      final data = map['data'];
      final results = map['results'];

      if (bars is List) {
        raw = List<dynamic>.from(bars);
      } else if (data is List) {
        raw = List<dynamic>.from(data);
      } else if (results is List) {
        raw = List<dynamic>.from(results);
      }
    } else if (decoded is List) {
      raw = List<dynamic>.from(decoded);
    }

    if (raw.isEmpty) {
      String details = '';

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);

        details = map['message']?.toString() ?? map['error']?.toString() ?? '';
      }

      throw Exception(
        details.isEmpty
            ? 'Biquote devolvió 0 velas para $symbol en $interval.'
            : 'Biquote: $details',
      );
    }

    final candles = <Candle>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final m = Map<String, dynamic>.from(item);

      final dt = _parseCandleTime(
        m['openTime'] ?? m['open_time'] ?? m['timestamp'] ?? m['time'],
      );

      final o = _num(m['open']);
      final h = _num(m['high']);
      final l = _num(m['low']);
      final c = _num(m['close']);

      if (dt == null || o == null || h == null || l == null || c == null) {
        continue;
      }

      final openFlag = m['isOpen'] ?? m['is_open'];

      final isOpen = openFlag == true ||
          openFlag?.toString().toLowerCase() == 'true' ||
          openFlag?.toString() == '1';

      // Nunca analizamos la vela que todavía está abierta.
      if (isOpen) {
        continue;
      }

      // Protección contra datos inválidos.
      if (o <= 0 || h <= 0 || l <= 0 || c <= 0) {
        continue;
      }

      if (h < l) {
        continue;
      }

      if (h < o || h < c || l > o || l > c) {
        continue;
      }

      candles.add(
        Candle(
          time: dt.toLocal(),
          open: o,
          high: h,
          low: l,
          close: c,
          volume: _num(m['volume']) ?? _num(m['tickVolume']) ?? 0,
        ),
      );
    }

    candles.sort(
      (a, b) => a.time.compareTo(b.time),
    );

    // Eliminar duplicados.
    final unique = <Candle>[];
    final seen = <int>{};

    for (final candle in candles) {
      final key = candle.time.millisecondsSinceEpoch;

      if (seen.add(key)) {
        unique.add(candle);
      }
    }

    if (unique.length < 60) {
      throw Exception(
        'Biquote devolvió ${unique.length} velas cerradas '
        'para $symbol. Se necesitan al menos 60.',
      );
    }

    return unique;
  }

  static DateTime? _parseCandleTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      final n = value.toInt();

      final millis = n.abs() < 100000000000 ? n * 1000 : n;

      return DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      );
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(text);

    if (parsed != null) {
      return parsed;
    }

    final numeric = num.tryParse(text);

    if (numeric != null) {
      final n = numeric.toInt();

      final millis = n.abs() < 100000000000 ? n * 1000 : n;

      return DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      );
    }

    return null;
  }

  static Future<double?> getCurrentPrice(
    String symbol,
  ) async {
    final normalized = normalizeSymbol(symbol);

    final response = await http.get(
      Uri.parse(
        '$baseUrl/$normalized',
      ),
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 8),
    );

    if (response.statusCode != 200) {
      return null;
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return null;
    }

    if (decoded is! Map) {
      return null;
    }

    final m = Map<String, dynamic>.from(
      decoded,
    );

    return _num(m['mid']) ?? _num(m['price']) ?? _num(m['close']);
  }

  static double? _num(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }
}

class TradingStrategy {
  static SignalResult analyze(
    List<Candle> candles,
  ) {
    final ema20 = _ema(
      candles.map((e) => e.close).toList(),
      20,
    );

    final ema50 = _ema(
      candles.map((e) => e.close).toList(),
      50,
    );

    final rsi = _rsi(
      candles,
      14,
    );

    final macdData = _macd(
      candles,
    );

    final adx = _adx(
      candles,
      14,
    );

    final last = candles.last;

    final bullishTrend = ema20 > ema50;

    final bearishTrend = ema20 < ema50;

    final bullishMomentum = macdData.$1 > macdData.$2 && rsi >= 50;

    final bearishMomentum = macdData.$1 < macdData.$2 && rsi <= 50;

    final pa = _priceAction(
      candles,
    );

    final call = _callScore(
      candles,
      bullishTrend,
      bullishMomentum,
      rsi,
      macdData,
      adx,
      pa,
    );

    final put = _putScore(
      candles,
      bearishTrend,
      bearishMomentum,
      rsi,
      macdData,
      adx,
      pa,
    );

    String action = 'WAIT';

    int score = max(
      call,
      put,
    );

    if (call >= 5 && call > put) {
      action = 'CALL';
    }

    if (put >= 5 && put > call) {
      action = 'PUT';
    }

    if (rsi >= 70 && action == 'CALL') {
      action = 'WAIT';
    }

    if (rsi <= 30 && action == 'PUT') {
      action = 'WAIT';
    }

    if (adx < 15) {
      action = 'WAIT';
    }

    final display = switch (action) {
      'CALL' => 'ALZA',
      'PUT' => 'BAJA',
      _ => 'ESPERAR',
    };

    final arrow = switch (action) {
      'CALL' => '↑',
      'PUT' => '↓',
      _ => '⏸',
    };

    final strength = switch (score) {
      >= 7 => 'MUY FUERTE',
      6 => 'FUERTE',
      5 => 'BUENA',
      _ => 'FILTRADA',
    };

    final reasons = <String>[
      'EMA20 ${bullishTrend ? "por encima" : bearishTrend ? "por debajo" : "cerca"} de EMA50',
      'RSI ${rsi.toStringAsFixed(1)}',
      'MACD ${macdData.$1 >= macdData.$2 ? "alcista" : "bajista"}',
      'ADX ${adx.toStringAsFixed(1)}',
      pa,
    ];

    return SignalResult(
      action: action,
      display: display,
      arrow: arrow,
      score: score,
      maxScore: 7,
      strength: strength,
      reason: reasons.join(' • '),
      trend: bullishTrend
          ? 'ALCISTA'
          : bearishTrend
              ? 'BAJISTA'
              : 'LATERAL',
      momentum: bullishMomentum
          ? 'ALCISTA'
          : bearishMomentum
              ? 'BAJISTA'
              : 'NEUTRO',
      priceAction: pa,
      rsi: rsi,
      ema20: ema20,
      ema50: ema50,
      macd: macdData.$1,
      macdSignal: macdData.$2,
      adx: adx,
      candle: last,
    );
  }

  static int _callScore(
    List<Candle> c,
    bool trend,
    bool momentum,
    double rsi,
    (double, double) macd,
    double adx,
    String pa,
  ) {
    var s = 0;

    if (trend) {
      s++;
    }

    if (momentum) {
      s++;
    }

    if (rsi > 50 && rsi < 70) {
      s++;
    }

    if (macd.$1 > macd.$2) {
      s++;
    }

    if (adx >= 15) {
      s++;
    }

    if (c.last.close > c.last.open) {
      s++;
    }

    if (pa.contains('ALCISTA')) {
      s++;
    }

    return s;
  }

  static int _putScore(
    List<Candle> c,
    bool trend,
    bool momentum,
    double rsi,
    (double, double) macd,
    double adx,
    String pa,
  ) {
    var s = 0;

    if (trend) {
      s++;
    }

    if (momentum) {
      s++;
    }

    if (rsi < 50 && rsi > 30) {
      s++;
    }

    if (macd.$1 < macd.$2) {
      s++;
    }

    if (adx >= 15) {
      s++;
    }

    if (c.last.close < c.last.open) {
      s++;
    }

    if (pa.contains('BAJISTA')) {
      s++;
    }

    return s;
  }

  static String _priceAction(
    List<Candle> c,
  ) {
    final last = c.last;

    final body = (last.close - last.open).abs();

    final range = max(
      last.high - last.low,
      1e-12,
    );

    final upper = last.high -
        max(
          last.open,
          last.close,
        );

    final lower = min(
          last.open,
          last.close,
        ) -
        last.low;

    if (last.close > last.open && lower > body * 1.5) {
      return 'ALCISTA — RECHAZO INFERIOR';
    }

    if (last.close < last.open && upper > body * 1.5) {
      return 'BAJISTA — RECHAZO SUPERIOR';
    }

    if (last.close > last.open && body / range > .65) {
      return 'ALCISTA — IMPULSO';
    }

    if (last.close < last.open && body / range > .65) {
      return 'BAJISTA — IMPULSO';
    }

    if (c.length >= 2) {
      final prev = c[c.length - 2];

      if (last.close > last.open &&
          prev.close < prev.open &&
          last.close > prev.open &&
          last.open < prev.close) {
        return 'ALCISTA — ENGULFING';
      }

      if (last.close < last.open &&
          prev.close > prev.open &&
          last.close < prev.open &&
          last.open > prev.close) {
        return 'BAJISTA — ENGULFING';
      }
    }

    return last.close >= last.open ? 'ALCISTA — VELA' : 'BAJISTA — VELA';
  }

  static double _ema(
    List<double> values,
    int period,
  ) {
    if (values.isEmpty) {
      return 0;
    }

    final alpha = 2 / (period + 1);

    var result = values.first;

    for (var i = 1; i < values.length; i++) {
      result = alpha * values[i] + (1 - alpha) * result;
    }

    return result;
  }

  static double _rsi(
    List<Candle> candles,
    int period,
  ) {
    if (candles.length <= period) {
      return 50;
    }

    var gains = 0.0;
    var losses = 0.0;

    for (var i = candles.length - period; i < candles.length; i++) {
      final d = candles[i].close - candles[i - 1].close;

      if (d >= 0) {
        gains += d;
      } else {
        losses -= d;
      }
    }

    if (losses == 0) {
      return 100;
    }

    final rs = (gains / period) / (losses / period);

    return 100 - (100 / (1 + rs));
  }

  static (double, double) _macd(
    List<Candle> candles,
  ) {
    final closes = candles
        .map(
          (e) => e.close,
        )
        .toList();

    final ema12 = _ema(
      closes,
      12,
    );

    final ema26 = _ema(
      closes,
      26,
    );

    final macd = ema12 - ema26;

    final values = <double>[];

    for (var i = 25; i < closes.length; i++) {
      final a = _ema(
        closes.sublist(
          0,
          i + 1,
        ),
        12,
      );

      final b = _ema(
        closes.sublist(
          0,
          i + 1,
        ),
        26,
      );

      values.add(
        a - b,
      );
    }

    final signal = values.isEmpty
        ? macd
        : _ema(
            values,
            9,
          );

    return (
      macd,
      signal,
    );
  }

  static double _adx(
    List<Candle> candles,
    int period,
  ) {
    if (candles.length < period + 2) {
      return 0;
    }

    var trSum = 0.0;
    var plusSum = 0.0;
    var minusSum = 0.0;

    final start = candles.length - period;

    for (var i = start; i < candles.length; i++) {
      final cur = candles[i];

      final prev = candles[i - 1];

      final tr = max(
        cur.high - cur.low,
        max(
          (cur.high - prev.close).abs(),
          (cur.low - prev.close).abs(),
        ),
      );

      final up = cur.high - prev.high;

      final down = prev.low - cur.low;

      trSum += tr;

      if (up > down && up > 0) {
        plusSum += up;
      }

      if (down > up && down > 0) {
        minusSum += down;
      }
    }

    if (trSum == 0) {
      return 0;
    }

    final plus = 100 * plusSum / trSum;

    final minus = 100 * minusSum / trSum;

    final denom = plus + minus;

    if (denom == 0) {
      return 0;
    }

    return 100 * (plus - minus).abs() / denom;
  }
}

class TradingAnalyzerPage extends StatefulWidget {
  const TradingAnalyzerPage({
    super.key,
  });

  @override
  State<TradingAnalyzerPage> createState() => _TradingAnalyzerPageState();
}

class _TradingAnalyzerPageState extends State<TradingAnalyzerPage> {
  final assets = const [
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'USD/CHF',
    'AUD/USD',
    'USD/CAD',
    'NZD/USD',
    'EUR/JPY',
    'GBP/JPY',
    'EUR/GBP',
    'AUD/JPY',
    'NZD/JPY',
    'CAD/JPY',
    'CHF/JPY',
  ];

  // IMPORTANTE:
  // Estos valores son EXPIRACIÓN.
  // Las velas utilizadas para el análisis
  // siempre son de 1 minuto.
  final expirations = const [
    '1m',
    '2m',
    '5m',
    '15m',
    '30m',
    '1h',
    '4h',
    '1d',
  ];

  String selectedAsset = 'EUR/USD';

  String selectedTimeframe = '1m';

  List<Candle> candles = [];

  SignalResult? signal;

  double? livePrice;

  String? errorMessage;

  bool analyzing = false;

  Duration? entryCountdown;

  Timer? countdownTimer;

  Timer? refreshTimer;

  HubConnection? hubConnection;

  @override
  void initState() {
    super.initState();

    analyze();

    _startLive();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();

    refreshTimer?.cancel();

    hubConnection?.stop();

    super.dispose();
  }

  Future<void> analyze() async {
    if (analyzing) {
      return;
    }

    countdownTimer?.cancel();

    setState(() {
      analyzing = true;
      errorMessage = null;
      signal = null;
      entryCountdown = null;
    });

    try {
      // TODAS las velas son 1 minuto.
      final data = await BiquoteService.getCandles(
        selectedAsset,
        interval: '1m',
        limit: 200,
      );

      final result = TradingStrategy.analyze(
        data,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        candles = data;
        signal = result;
        analyzing = false;
      });

      // El contador SOLO aparece si hay CALL o PUT.
      if (result.action != 'WAIT') {
        _startEntryCountdown(
          result.candle,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        analyzing = false;
        errorMessage = e.toString();
      });
    }
  }

  void _startEntryCountdown(
    Candle base,
  ) {
    countdownTimer?.cancel();

    /*
      base = última vela 1M cerrada.

      Si la vela cerró a las 10:06,
      la siguiente vela empieza a las 10:06
      y termina a las 10:07.

      Por eso utilizamos +2 minutos
      desde el openTime de la vela base.

      Este contador NO es la expiración.
      Es únicamente el momento de entrada.
    */

    final nextClose = DateTime(
      base.time.year,
      base.time.month,
      base.time.day,
      base.time.hour,
      base.time.minute + 2,
    );

    void tick() {
      if (!mounted || signal == null || signal!.action == 'WAIT') {
        countdownTimer?.cancel();
        return;
      }

      final left = nextClose.difference(
        DateTime.now(),
      );

      setState(() {
        entryCountdown = Duration(
          seconds: max(
            0,
            left.inSeconds,
          ),
        );
      });

      if (left.inSeconds <= 0) {
        countdownTimer?.cancel();
      }
    }

    tick();

    countdownTimer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
      (_) => tick(),
    );
  }

  Future<void> _startLive() async {
    refreshTimer = Timer.periodic(
      const Duration(
        seconds: 5,
      ),
      (_) => _refreshLive(),
    );

    await _refreshLive();

    await _connectSignalR();
  }

  Future<void> _refreshLive() async {
    try {
      final price = await BiquoteService.getCurrentPrice(
        selectedAsset,
      );

      if (mounted && price != null) {
        setState(() {
          livePrice = price;
        });
      }
    } catch (_) {}
  }

  Future<void> _connectSignalR() async {
    try {
      final connection = HubConnectionBuilder()
          .withUrl(
        BiquoteService.hubUrl,
      )
          .withAutomaticReconnect(
        retryDelays: [
          2000,
          5000,
          10000,
          20000,
        ],
      ).build();

      hubConnection = connection;

      connection.on(
        'ReceiveTick',
        (arguments) {
          if (!mounted || arguments == null || arguments.isEmpty) {
            return;
          }

          final first = arguments.first;

          if (first is Map) {
            final map = Map<String, dynamic>.from(
              first,
            );

            final symbol = map['symbol']?.toString().replaceAll(
                  '/',
                  '',
                );

            if (symbol ==
                BiquoteService.normalizeSymbol(
                  selectedAsset,
                )) {
              final price = _readPrice(
                map,
              );

              if (price != null && mounted) {
                setState(() {
                  livePrice = price;
                });
              }
            }
          }
        },
      );

      await connection.start();

      await connection.invoke(
        'Subscribe',
        args: [
          [
            BiquoteService.normalizeSymbol(
              selectedAsset,
            ),
          ],
        ],
      );
    } catch (_) {
      // Si SignalR falla,
      // seguimos utilizando REST.
    }
  }

  double? _readPrice(
    Map<String, dynamic> m,
  ) {
    for (final key in [
      'mid',
      'price',
      'close',
      'bid',
      'ask',
    ]) {
      final v = m[key];

      if (v is num) {
        return v.toDouble();
      }

      final d = double.tryParse(
        v?.toString() ?? '',
      );

      if (d != null) {
        return d;
      }
    }

    return null;
  }

  String _price(
    double value,
  ) {
    if (value >= 100) {
      return value.toStringAsFixed(
        2,
      );
    }

    if (value >= 10) {
      return value.toStringAsFixed(
        3,
      );
    }

    return value.toStringAsFixed(
      5,
    );
  }

  String _expirationLabel() {
    switch (selectedTimeframe) {
      case '1m':
        return '1 minuto';

      case '2m':
        return '2 minutos';

      case '5m':
        return '5 minutos';

      case '15m':
        return '15 minutos';

      case '30m':
        return '30 minutos';

      case '1h':
        return '1 hora';

      case '4h':
        return '4 horas';

      case '1d':
        return '1 día';

      default:
        return selectedTimeframe;
    }
  }

  String _countdownText() {
    final d = entryCountdown;

    if (d == null) {
      return '--:--';
    }

    final s = max(
      0,
      d.inSeconds,
    );

    final mm = (s ~/ 60).toString().padLeft(
          2,
          '0',
        );

    final ss = (s % 60).toString().padLeft(
          2,
          '0',
        );

    return '$mm:$ss';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final s = signal;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trading Signal Bot',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: analyzing ? null : analyze,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: analyze,
          child: ListView(
            padding: const EdgeInsets.all(
              14,
            ),
            children: [
              _buildSelectors(),

              const SizedBox(
                height: 12,
              ),

              // BOTÓN ANALIZAR
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: analyzing ? null : analyze,
                  icon: analyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.analytics_outlined,
                        ),
                  label: Text(
                    analyzing ? 'ANALIZANDO...' : 'ANALIZAR',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              _buildPriceCard(),

              const SizedBox(
                height: 12,
              ),

              if (errorMessage != null) _buildErrorCard(),

              if (analyzing)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 40,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              if (!analyzing && s != null) ...[
                _buildSignalCard(
                  s,
                ),
                const SizedBox(
                  height: 12,
                ),
                _buildEntryCard(
                  s,
                ),
                const SizedBox(
                  height: 12,
                ),
                _buildChart(),
                const SizedBox(
                  height: 12,
                ),
                _buildIndicators(
                  s,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectors() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CONFIGURACIÓN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedAsset,
                    decoration: const InputDecoration(
                      labelText: 'Activo',
                      border: OutlineInputBorder(),
                    ),
                    items: assets
                        .map(
                          (
                            a,
                          ) =>
                              DropdownMenuItem(
                            value: a,
                            child: Text(
                              a,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) {
                        return;
                      }

                      setState(() {
                        selectedAsset = v;

                        signal = null;

                        entryCountdown = null;
                      });

                      await analyze();
                    },
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedTimeframe,
                    decoration: const InputDecoration(
                      labelText: 'EXPIRACIÓN',
                      border: OutlineInputBorder(),
                    ),
                    items: expirations
                        .map(
                          (
                            t,
                          ) =>
                              DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) {
                        return;
                      }

                      setState(() {
                        selectedTimeframe = v;
                      });

                      if (signal != null && signal!.action != 'WAIT') {
                        _startEntryCountdown(
                          signal!.candle,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'Las velas utilizadas para el análisis siempre son de 1 minuto. La selección anterior solamente cambia la expiración de la operación.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.show_chart,
            ),
            const SizedBox(
              width: 12,
            ),
            const Text(
              'Precio actual',
            ),
            const Spacer(),
            Text(
              livePrice == null
                  ? '--'
                  : _price(
                      livePrice!,
                    ),
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalCard(
    SignalResult s,
  ) {
    final isCall = s.action == 'CALL';

    final isPut = s.action == 'PUT';

    final title = isCall
        ? 'ALZA'
        : isPut
            ? 'BAJA'
            : 'ESPERAR';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          18,
        ),
        child: Column(
          children: [
            Text(
              '$title ${s.arrow}',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: isCall
                    ? Colors.greenAccent
                    : isPut
                        ? Colors.redAccent
                        : Colors.amberAccent,
              ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              s.strength,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            LinearProgressIndicator(
              value: s.score / s.maxScore,
              minHeight: 8,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'Puntuación ${s.score}/${s.maxScore}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              s.reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(
    SignalResult s,
  ) {
    // IMPORTANTE:
    // Si WAIT, NO mostramos contador.
    if (s.action == 'WAIT' || entryCountdown == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(
            16,
          ),
          child: Row(
            children: const [
              Icon(
                Icons.hourglass_empty,
              ),
              SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Sin señal de entrada. El contador aparece únicamente cuando existe ALZA o BAJA.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ready = entryCountdown!.inSeconds <= 0;

    final label = s.action == 'CALL' ? 'CALL' : 'PUT';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          18,
        ),
        child: Column(
          children: [
            Text(
              ready ? 'ENTRAR $label AHORA' : 'PUNTO DE ENTRADA',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              ready
                  ? 'La siguiente vela 1M terminó. Ejecuta la operación manualmente.'
                  : 'Espera el cierre de la siguiente vela 1M.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              _countdownText(),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Expiración seleccionada: ${_expirationLabel()}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }

    final shown = candles.length > 80
        ? candles.sublist(
            candles.length - 80,
          )
        : candles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          8,
          16,
          8,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Text(
                'GRÁFICO 1M',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            SizedBox(
              height: 310,
              child: SfCartesianChart(
                zoomPanBehavior: ZoomPanBehavior(
                  enablePinching: true,
                  enablePanning: true,
                  enableMouseWheelZooming: true,
                ),
                primaryXAxis: DateTimeAxis(
                  dateFormat: DateFormat(
                    'HH:mm',
                  ),
                  intervalType: DateTimeIntervalType.minutes,
                ),
                series: <CartesianSeries<Candle, DateTime>>[
                  CandleSeries<Candle, DateTime>(
                    dataSource: shown,
                    xValueMapper: (
                      c,
                      _,
                    ) =>
                        c.time,
                    lowValueMapper: (
                      c,
                      _,
                    ) =>
                        c.low,
                    highValueMapper: (
                      c,
                      _,
                    ) =>
                        c.high,
                    openValueMapper: (
                      c,
                      _,
                    ) =>
                        c.open,
                    closeValueMapper: (
                      c,
                      _,
                    ) =>
                        c.close,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicators(
    SignalResult s,
  ) {
    Widget item(
      String name,
      String value,
    ) {
      return Expanded(
        child: Column(
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white54,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INDICADORES',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            Row(
              children: [
                item(
                  'EMA 20',
                  _price(
                    s.ema20,
                  ),
                ),
                item(
                  'EMA 50',
                  _price(
                    s.ema50,
                  ),
                ),
                item(
                  'RSI',
                  s.rsi.toStringAsFixed(
                    1,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 18,
            ),
            Row(
              children: [
                item(
                  'MACD',
                  s.macd.toStringAsFixed(
                    6,
                  ),
                ),
                item(
                  'SIGNAL',
                  s.macdSignal.toStringAsFixed(
                    6,
                  ),
                ),
                item(
                  'ADX',
                  s.adx.toStringAsFixed(
                    1,
                  ),
                ),
              ],
            ),
            const Divider(
              height: 28,
            ),
            Text(
              'Tendencia: ${s.trend}',
            ),
            Text(
              'Momentum: ${s.momentum}',
            ),
            Text(
              'Acción del precio: ${s.priceAction}',
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Última vela: ${DateFormat('yyyy-MM-dd HH:mm').format(s.candle.time)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                errorMessage ?? 'Error desconocido',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
