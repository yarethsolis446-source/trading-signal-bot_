import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

// El TIMEFRAME seleccionado controla el análisis.
// La ENTRADA de la operación siempre ocurre en la apertura de la siguiente vela 1M.
// La expiración visual sigue siendo el timeframe seleccionado.

// ============================================================
// TIMEFRAME + 1M ENTRY
// ============================================================
// El timeframe seleccionado controla el análisis.
// La entrada manual siempre se realiza en la apertura de la siguiente vela 1M.

// ============================================================
// CANDLE
// ============================================================

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final bool isOpen;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.isOpen = false,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    final timeValue = json['openTime'] ??
        json['time'] ??
        json['timestamp'] ??
        json['date'] ??
        json['datetime'];

    DateTime parsedTime;

    if (timeValue is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(
        timeValue > 1000000000000 ? timeValue : timeValue * 1000,
        isUtc: true,
      ).toLocal();
    } else {
      parsedTime = DateTime.tryParse(timeValue?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    return Candle(
      time: parsedTime,
      open: _toDouble(json['open']),
      high: _toDouble(json['high']),
      low: _toDouble(json['low']),
      close: _toDouble(json['close']),
      isOpen: json['isOpen'] == true,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

// ============================================================
// SIGNAL RESULT
// ============================================================

class SignalResult {
  final String action;
  final String direction;
  final String strength;
  final int score;
  final double ema20;
  final double ema50;
  final double rsi;
  final double macd;
  final double macdSignal;
  final double adx;
  final double atr;
  final double entryPrice;
  final String trend;
  final String higherTrend;
  final String structure;
  final String priceAction;
  final String levelStatus;
  final String setup;
  final String setupStatus;
  final List<String> reasons;
  final String entryTiming;
  final DateTime? plannedEntryTime;

  SignalResult({
    required this.action,
    required this.direction,
    required this.strength,
    required this.score,
    required this.ema20,
    required this.ema50,
    required this.rsi,
    required this.macd,
    required this.macdSignal,
    required this.adx,
    required this.atr,
    required this.entryPrice,
    required this.trend,
    required this.higherTrend,
    required this.structure,
    required this.priceAction,
    required this.levelStatus,
    required this.setup,
    required this.setupStatus,
    required this.reasons,
    required this.entryTiming,
    required this.plannedEntryTime,
  });
}

// ============================================================
// PRICE ACTION
// ============================================================

class PriceActionAnalysis {
  final bool bullishStructure;
  final bool bearishStructure;
  final bool bullishBos;
  final bool bearishBos;
  final bool bullishPullback;
  final bool bearishPullback;
  final bool bullishRejection;
  final bool bearishRejection;
  final bool bullishEngulfing;
  final bool bearishEngulfing;
  final bool bullishImpulse;
  final bool bearishImpulse;
  final bool nearSupport;
  final bool nearResistance;
  final bool goodCallSpace;
  final bool goodPutSpace;
  final String structure;
  final String pattern;
  final double support;
  final double resistance;

  const PriceActionAnalysis({
    required this.bullishStructure,
    required this.bearishStructure,
    required this.bullishBos,
    required this.bearishBos,
    required this.bullishPullback,
    required this.bearishPullback,
    required this.bullishRejection,
    required this.bearishRejection,
    required this.bullishEngulfing,
    required this.bearishEngulfing,
    required this.bullishImpulse,
    required this.bearishImpulse,
    required this.nearSupport,
    required this.nearResistance,
    required this.goodCallSpace,
    required this.goodPutSpace,
    required this.structure,
    required this.pattern,
    required this.support,
    required this.resistance,
  });

  static PriceActionAnalysis analyze(
    List<Candle> candles,
    double ema20,
    double atr,
  ) {
    if (candles.length < 20 || atr <= 0) {
      return const PriceActionAnalysis(
        bullishStructure: false,
        bearishStructure: false,
        bullishBos: false,
        bearishBos: false,
        bullishPullback: false,
        bearishPullback: false,
        bullishRejection: false,
        bearishRejection: false,
        bullishEngulfing: false,
        bearishEngulfing: false,
        bullishImpulse: false,
        bearishImpulse: false,
        nearSupport: false,
        nearResistance: false,
        goodCallSpace: false,
        goodPutSpace: false,
        structure: 'NEUTRAL',
        pattern: 'SIN CONFIRMACIÓN',
        support: 0,
        resistance: 0,
      );
    }

    final pivotsHigh = <double>[];
    final pivotsLow = <double>[];
    final pivotHighIndexes = <int>[];
    final pivotLowIndexes = <int>[];

    // Pivotes objetivos: 2 velas a cada lado.
    for (int i = 2; i < candles.length - 2; i++) {
      final c = candles[i];
      bool highPivot = true;
      bool lowPivot = true;
      for (int j = 1; j <= 2; j++) {
        if (c.high <= candles[i - j].high || c.high <= candles[i + j].high) {
          highPivot = false;
        }
        if (c.low >= candles[i - j].low || c.low >= candles[i + j].low) {
          lowPivot = false;
        }
      }
      if (highPivot) {
        pivotsHigh.add(c.high);
        pivotHighIndexes.add(i);
      }
      if (lowPivot) {
        pivotsLow.add(c.low);
        pivotLowIndexes.add(i);
      }
    }

    final highs = pivotsHigh.length > 6
        ? pivotsHigh.sublist(pivotsHigh.length - 6)
        : pivotsHigh;
    final lows = pivotsLow.length > 6
        ? pivotsLow.sublist(pivotsLow.length - 6)
        : pivotsLow;

    bool bullishStructure = highs.length >= 2 &&
        lows.length >= 2 &&
        highs[highs.length - 1] > highs[highs.length - 2] &&
        lows[lows.length - 1] > lows[lows.length - 2];
    bool bearishStructure = highs.length >= 2 &&
        lows.length >= 2 &&
        highs[highs.length - 1] < highs[highs.length - 2] &&
        lows[lows.length - 1] < lows[lows.length - 2];

    final last = candles.last;
    final previous = candles[candles.length - 2];
    final previousHigh = pivotsHigh.isEmpty ? 0.0 : pivotsHigh.last;
    final previousLow = pivotsLow.isEmpty ? 0.0 : pivotsLow.last;

    final bullishBos = previousHigh > 0 &&
        last.close > previousHigh &&
        previous.close <= previousHigh;
    final bearishBos = previousLow > 0 &&
        last.close < previousLow &&
        previous.close >= previousLow;

    final distanceToEma = (last.close - ema20).abs();
    final nearEma = distanceToEma <= atr * 0.45;
    final bullishPullback = nearEma &&
        ((last.close > last.open && previous.close < previous.open) ||
            bullishStructure);
    final bearishPullback = nearEma &&
        ((last.close < last.open && previous.close > previous.open) ||
            bearishStructure);

    final range = max(last.high - last.low, 0.0000000001).toDouble();
    final body = (last.close - last.open).abs();
    final upperWick = last.high - max(last.open, last.close);
    final lowerWick = min(last.open, last.close) - last.low;

    final bullishRejection =
        lowerWick / range >= 0.35 && last.close >= last.low + range * 0.62;
    final bearishRejection =
        upperWick / range >= 0.35 && last.close <= last.high - range * 0.62;

    final bullishEngulfing = previous.close < previous.open &&
        last.close > last.open &&
        last.open <= previous.close &&
        last.close >= previous.open;
    final bearishEngulfing = previous.close > previous.open &&
        last.close < last.open &&
        last.open >= previous.close &&
        last.close <= previous.open;

    final bullishImpulse =
        last.close > last.open && body / range >= 0.60 && body >= atr * 0.55;
    final bearishImpulse =
        last.close < last.open && body / range >= 0.60 && body >= atr * 0.55;

    double support = 0.0;
    for (final level in pivotsLow.reversed) {
      if (level < last.close) {
        support = level;
        break;
      }
    }
    double resistance = 0.0;
    for (final level in pivotsHigh.reversed) {
      if (level > last.close) {
        resistance = level;
        break;
      }
    }

    final nearSupport = support > 0 && (last.close - support) <= atr * 0.60;
    final nearResistance =
        resistance > 0 && (resistance - last.close) <= atr * 0.60;
    final callSpace =
        resistance <= 0 || (resistance - last.close) >= atr * 1.20;
    final putSpace = support <= 0 || (last.close - support) >= atr * 1.20;

    String structure = 'NEUTRAL';
    if (bullishStructure) {
      structure = 'HH + HL';
    }
    if (bearishStructure) {
      structure = 'LH + LL';
    }
    if (bullishBos) {
      structure = 'BOS ALCISTA';
    }
    if (bearishBos) {
      structure = 'BOS BAJISTA';
    }

    String pattern = 'SIN CONFIRMACIÓN';
    if (bullishEngulfing) {
      pattern = 'ENGULFING ALCISTA';
    } else if (bearishEngulfing) {
      pattern = 'ENGULFING BAJISTA';
    } else if (bullishRejection) {
      pattern = 'RECHAZO ALCISTA';
    } else if (bearishRejection) {
      pattern = 'RECHAZO BAJISTA';
    } else if (bullishImpulse) {
      pattern = 'IMPULSO ALCISTA';
    } else if (bearishImpulse) {
      pattern = 'IMPULSO BAJISTA';
    } else if (bullishPullback) {
      pattern = 'PULLBACK ALCISTA';
    } else if (bearishPullback) {
      pattern = 'PULLBACK BAJISTA';
    }

    return PriceActionAnalysis(
      bullishStructure: bullishStructure,
      bearishStructure: bearishStructure,
      bullishBos: bullishBos,
      bearishBos: bearishBos,
      bullishPullback: bullishPullback,
      bearishPullback: bearishPullback,
      bullishRejection: bullishRejection,
      bearishRejection: bearishRejection,
      bullishEngulfing: bullishEngulfing,
      bearishEngulfing: bearishEngulfing,
      bullishImpulse: bullishImpulse,
      bearishImpulse: bearishImpulse,
      nearSupport: nearSupport,
      nearResistance: nearResistance,
      goodCallSpace: callSpace,
      goodPutSpace: putSpace,
      structure: structure,
      pattern: pattern,
      support: support,
      resistance: resistance,
    );
  }
}

// ============================================================
// BIQUOTE SERVICE
// ============================================================

class BiquoteService {
  static const String baseUrl = 'https://biquote.io/api';

  static String normalizeSymbol(String symbol) {
    return symbol.replaceAll('/', '');
  }

  // ==========================================================
  // OHLC
  // ==========================================================

  static Future<List<Candle>> getCandles(
    String symbol,
    String timeframe,
  ) async {
    // --------------------------------------------------------
    // 2 MINUTOS
    // Biquote no tiene 2m nativo.
    // Construimos 2m usando velas de 1m.
    // --------------------------------------------------------

    if (timeframe == '2m') {
      final oneMinute = await getCandles(symbol, '1m');

      return _aggregateTwoMinutes(oneMinute);
    }

    final normalized = normalizeSymbol(symbol);

    final url = Uri.parse(
      '$baseUrl/$normalized/ohlc'
      '?interval=$timeframe'
      '&limit=200',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      String message = 'Error HTTP ${response.statusCode}';

      try {
        final body = jsonDecode(response.body);

        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        }
      } catch (_) {}

      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {
      throw Exception('Respuesta OHLC inválida.');
    }

    final rawBars = decoded['bars'];

    if (rawBars is! List) {
      throw Exception('Biquote no devolvió una lista de velas.');
    }

    final result = <Candle>[];

    for (final item in rawBars) {
      if (item is! Map) {
        continue;
      }

      final candle = Candle.fromJson(Map<String, dynamic>.from(item));

      if (!_validCandle(candle)) {
        continue;
      }

      result.add(candle);
    }

    result.sort((a, b) => a.time.compareTo(b.time));

    return result;
  }

  // ==========================================================
  // VALIDAR VELA
  // ==========================================================

  static bool _validCandle(Candle c) {
    if (!c.open.isFinite ||
        !c.high.isFinite ||
        !c.low.isFinite ||
        !c.close.isFinite) {
      return false;
    }

    if (c.open <= 0 || c.high <= 0 || c.low <= 0 || c.close <= 0) {
      return false;
    }

    final highest = max(c.open, c.close).toDouble();
    final lowest = min(c.open, c.close).toDouble();

    if (c.high < highest) {
      return false;
    }

    if (c.low > lowest) {
      return false;
    }

    return true;
  }

  // ==========================================================
  // AGREGAR 1m -> 2m
  // ==========================================================

  static List<Candle> _aggregateTwoMinutes(List<Candle> source) {
    if (source.isEmpty) {
      return [];
    }

    final sorted = [...source]..sort((a, b) => a.time.compareTo(b.time));

    final Map<DateTime, List<Candle>> groups = {};

    for (final candle in sorted) {
      final minute = candle.time.minute;

      final bucketMinute = minute - (minute % 2);

      final bucket = DateTime(
        candle.time.year,
        candle.time.month,
        candle.time.day,
        candle.time.hour,
        bucketMinute,
      );

      groups.putIfAbsent(bucket, () => []).add(candle);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final result = <Candle>[];

    for (final entry in entries) {
      final group = entry.value;

      if (group.isEmpty) {
        continue;
      }

      final first = group.first;
      final last = group.last;

      double high = first.high;
      double low = first.low;

      for (final candle in group) {
        high = max(high, candle.high).toDouble();
        low = min(low, candle.low).toDouble();
      }

      final isOpen = group.any((c) => c.isOpen);

      result.add(
        Candle(
          time: entry.key,
          open: first.open,
          high: high,
          low: low,
          close: last.close,
          isOpen: isOpen,
        ),
      );
    }

    return result;
  }

  // ==========================================================
  // PRECIO ACTUAL
  // ==========================================================

  static Future<double?> getCurrentPrice(String symbol) async {
    final normalized = normalizeSymbol(symbol);

    final url = Uri.parse('$baseUrl/$normalized');

    final response = await http.get(url).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {
      return null;
    }

    final mid = decoded['mid'];

    if (mid is num) {
      final value = mid.toDouble();

      if (value.isFinite && value > 0) {
        return value;
      }
    }

    return null;
  }
}

// ============================================================
// INDICATORS
// ============================================================

class Indicators {
  static double ema(List<double> values, int period) {
    if (values.isEmpty) {
      return 0.0;
    }

    if (values.length < period) {
      return values.last;
    }

    final multiplier = 2.0 / (period + 1);

    double value = values.take(period).reduce((a, b) => a + b) / period;

    for (int i = period; i < values.length; i++) {
      value = (values[i] - value) * multiplier + value;
    }

    return value;
  }

  static double rsi(List<double> closes, int period) {
    if (closes.length <= period) {
      return 50.0;
    }

    double gain = 0.0;
    double loss = 0.0;

    for (int i = 1; i <= period; i++) {
      final difference = closes[i] - closes[i - 1];

      if (difference >= 0) {
        gain += difference;
      } else {
        loss += difference.abs();
      }
    }

    double avgGain = gain / period;
    double avgLoss = loss / period;

    for (int i = period + 1; i < closes.length; i++) {
      final difference = closes[i] - closes[i - 1];

      final currentGain = difference > 0 ? difference : 0.0;

      final currentLoss = difference < 0 ? difference.abs() : 0.0;

      avgGain = ((avgGain * (period - 1)) + currentGain) / period;

      avgLoss = ((avgLoss * (period - 1)) + currentLoss) / period;
    }

    if (avgLoss == 0) {
      return 100.0;
    }

    final rs = avgGain / avgLoss;

    return 100.0 - (100.0 / (1.0 + rs));
  }

  static Map<String, double> macd(List<double> closes) {
    if (closes.length < 35) {
      return {'macd': 0.0, 'signal': 0.0};
    }

    final values = <double>[];

    for (int i = 0; i < closes.length; i++) {
      final partial = closes.sublist(0, i + 1);

      final e12 = ema(partial, 12);
      final e26 = ema(partial, 26);

      values.add(e12 - e26);
    }

    return {'macd': values.last, 'signal': ema(values, 9)};
  }

  static double atr(List<Candle> candles, int period) {
    if (candles.length < period + 1) {
      return 0.0;
    }

    final trs = <double>[];

    for (int i = 1; i < candles.length; i++) {
      final current = candles[i];
      final previous = candles[i - 1];

      final tr1 = current.high - current.low;
      final tr2 = (current.high - previous.close).abs();
      final tr3 = (current.low - previous.close).abs();

      trs.add(max(tr1, max(tr2, tr3)).toDouble());
    }

    if (trs.length < period) {
      return 0.0;
    }

    double value = trs.take(period).reduce((a, b) => a + b) / period;

    for (int i = period; i < trs.length; i++) {
      value = ((value * (period - 1)) + trs[i]) / period;
    }

    return value;
  }

  static double adx(List<Candle> candles, int period) {
    if (candles.length < period * 2) {
      return 0.0;
    }

    final trList = <double>[];
    final plusList = <double>[];
    final minusList = <double>[];

    for (int i = 1; i < candles.length; i++) {
      final current = candles[i];
      final previous = candles[i - 1];

      final upMove = current.high - previous.high;

      final downMove = previous.low - current.low;

      double plus = 0.0;
      double minus = 0.0;

      if (upMove > downMove && upMove > 0) {
        plus = upMove;
      }

      if (downMove > upMove && downMove > 0) {
        minus = downMove;
      }

      final tr1 = current.high - current.low;
      final tr2 = (current.high - previous.close).abs();
      final tr3 = (current.low - previous.close).abs();

      final tr = max(tr1, max(tr2, tr3)).toDouble();

      trList.add(tr);
      plusList.add(plus);
      minusList.add(minus);
    }

    if (trList.length < period) {
      return 0.0;
    }

    double tr = trList.take(period).reduce((a, b) => a + b) / period;

    double plus = plusList.take(period).reduce((a, b) => a + b) / period;

    double minus = minusList.take(period).reduce((a, b) => a + b) / period;

    final dx = <double>[];

    for (int i = period; i < trList.length; i++) {
      tr = ((tr * (period - 1)) + trList[i]) / period;

      plus = ((plus * (period - 1)) + plusList[i]) / period;

      minus = ((minus * (period - 1)) + minusList[i]) / period;

      if (tr == 0) {
        continue;
      }

      final plusDI = 100.0 * plus / tr;
      final minusDI = 100.0 * minus / tr;

      final denominator = plusDI + minusDI;

      if (denominator == 0) {
        dx.add(0.0);
      } else {
        dx.add(100.0 * (plusDI - minusDI).abs() / denominator);
      }
    }

    if (dx.length < period) {
      return 0.0;
    }

    double result = dx.take(period).reduce((a, b) => a + b) / period;

    for (int i = period; i < dx.length; i++) {
      result = ((result * (period - 1)) + dx[i]) / period;
    }

    return result;
  }
}

// ============================================================
// STRATEGY
// ============================================================

class TradingStrategy {
  static DateTime _nextOneMinuteOpen() {
    final now = DateTime.now();
    final currentMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    return currentMinute.add(const Duration(minutes: 1));
  }

  static SignalResult analyze(
    List<Candle> candles,
    String timeframe,
  ) {
    if (candles.length < 60) {
      throw Exception('No hay suficientes velas para analizar.');
    }

    final closes = candles.map((c) => c.close).toList();
    final ema20 = Indicators.ema(closes, 20);
    final ema50 = Indicators.ema(closes, 50);
    final rsi = Indicators.rsi(closes, 14);
    final macd = Indicators.macd(closes);
    final adx = Indicators.adx(candles, 14);
    final atr = Indicators.atr(candles, 14);
    final last = candles.last;
    final previous = candles[candles.length - 2];
    final pa = PriceActionAnalysis.analyze(candles, ema20, atr);

    final previousCloses = closes.length >= 23
        ? closes.sublist(closes.length - 23, closes.length - 1)
        : closes.sublist(0, closes.length - 1);
    final previousEma20 = Indicators.ema(previousCloses, 20);
    final emaSlope = ema20 - previousEma20;
    final histogram = macd['macd']! - macd['signal']!;
    final atrSafe = atr > 0 ? atr : (last.close * 0.0001);

    String trend = 'NEUTRAL';
    if (ema20 > ema50 && emaSlope > 0) {
      trend = 'ALCISTA';
    }
    if (ema20 < ema50 && emaSlope < 0) {
      trend = 'BAJISTA';
    }

    // Esta versión no usa una temporalidad superior.
    const higherTrend = 'NO USADO';

    // ==========================================================
    // V4 PRICE ACTION DOMINANT + FREQUENT SIGNALS
    // La acción del precio manda claramente. Los indicadores solo CONFIRMAN.
    // ==========================================================
    int callDirection = 0;
    int putDirection = 0;
    int callPriceAction = 0;
    int putPriceAction = 0;
    final callReasons = <String>[];
    final putReasons = <String>[];
    final callSetupReasons = <String>[];
    final putSetupReasons = <String>[];

    final bullishCandle = last.close > last.open;
    final bearishCandle = last.close < last.open;
    final previousBullish = previous.close > previous.open;
    final previousBearish = previous.close < previous.open;

    // ==========================================================
    // MICRO PRICE ACTION EXTRA — TIMEFRAME SELECCIONADO
    // Más peso a la lectura directa de las últimas velas.
    // ==========================================================
    final microStart = candles.length >= 6 ? candles.length - 6 : 0;
    final microWindow = candles.sublist(microStart, candles.length - 1);
    final microHigh = microWindow.map((c) => c.high).reduce(max).toDouble();
    final microLow = microWindow.map((c) => c.low).reduce(min).toDouble();
    final microBreakCall = bullishCandle && last.close > microHigh;
    final microBreakPut = bearishCandle && last.close < microLow;
    final lastRange = max(last.high - last.low, 0.0000000001).toDouble();
    final lastBody = (last.close - last.open).abs();
    final upperWick = last.high - max(last.open, last.close);
    final lowerWick = min(last.open, last.close) - last.low;
    final pinCall = lowerWick / lastRange >= 0.28 &&
        last.close >= last.low + lastRange * 0.58;
    final pinPut = upperWick / lastRange >= 0.28 &&
        last.close <= last.high - lastRange * 0.58;
    final strongCloseCall = bullishCandle &&
        lastBody / lastRange >= 0.45 &&
        last.close >= last.high - lastRange * 0.25;
    final strongClosePut = bearishCandle &&
        lastBody / lastRange >= 0.45 &&
        last.close <= last.low + lastRange * 0.25;
    final twoBull =
        bullishCandle && previousBullish && last.close > previous.close;
    final twoBear =
        bearishCandle && previousBearish && last.close < previous.close;

    // ----------------------------------------------------------
    // PRICE ACTION: 45 puntos
    // ----------------------------------------------------------
    if (pa.bullishBos) {
      callPriceAction += 16;
      callReasons.add('BOS alcista confirmado');
    }
    if (pa.bearishBos) {
      putPriceAction += 16;
      putReasons.add('BOS bajista confirmado');
    }

    if (pa.bullishStructure) {
      callPriceAction += 10;
      callReasons.add('Estructura HH + HL');
    }
    if (pa.bearishStructure) {
      putPriceAction += 10;
      putReasons.add('Estructura LH + LL');
    }

    if (pa.bullishPullback) {
      callPriceAction += 9;
      callReasons.add('Pullback alcista');
    }
    if (pa.bearishPullback) {
      putPriceAction += 9;
      putReasons.add('Pullback bajista');
    }

    if (pa.bullishRejection) {
      callPriceAction += 8;
      callReasons.add('Rechazo alcista');
    }
    if (pa.bearishRejection) {
      putPriceAction += 8;
      putReasons.add('Rechazo bajista');
    }

    if (pa.bullishEngulfing) {
      callPriceAction += 8;
      callReasons.add('Engulfing alcista');
    }
    if (pa.bearishEngulfing) {
      putPriceAction += 8;
      putReasons.add('Engulfing bajista');
    }

    if (pa.bullishImpulse) {
      callPriceAction += 6;
      callReasons.add('Impulso alcista');
    }
    if (pa.bearishImpulse) {
      putPriceAction += 6;
      putReasons.add('Impulso bajista');
    }

    if (bullishCandle) {
      callPriceAction += 5;
      callReasons.add('Última vela alcista');
    }
    if (bearishCandle) {
      putPriceAction += 5;
      putReasons.add('Última vela bajista');
    }

    // Confirmaciones micro del timeframe seleccionado: suman oportunidades sin exigir indicadores.
    if (microBreakCall) {
      callPriceAction += 10;
      callReasons.add('Ruptura micro de máximo');
    }
    if (microBreakPut) {
      putPriceAction += 10;
      putReasons.add('Ruptura micro de mínimo');
    }
    if (pinCall) {
      callPriceAction += 6;
      callReasons.add('Pin/rechazo alcista');
    }
    if (pinPut) {
      putPriceAction += 6;
      putReasons.add('Pin/rechazo bajista');
    }
    if (strongCloseCall) {
      callPriceAction += 4;
      callReasons.add('Cierre fuerte alcista');
    }
    if (strongClosePut) {
      putPriceAction += 4;
      putReasons.add('Cierre fuerte bajista');
    }
    if (twoBull) {
      callPriceAction += 5;
      callReasons.add('Dos velas alcistas');
    }
    if (twoBear) {
      putPriceAction += 5;
      putReasons.add('Dos velas bajistas');
    }

    callPriceAction = min(callPriceAction, 55);
    putPriceAction = min(putPriceAction, 55);

    // ----------------------------------------------------------
    // ESTRUCTURA Y NIVELES: 35 puntos
    // ----------------------------------------------------------
    if (pa.bullishStructure) {
      callDirection += 20;
    }
    if (pa.bearishStructure) {
      putDirection += 20;
    }

    if (pa.nearSupport) {
      callDirection += 8;
      callReasons.add('Precio reaccionando cerca de soporte');
    }
    if (pa.nearResistance) {
      putDirection += 8;
      putReasons.add('Precio reaccionando cerca de resistencia');
    }

    if (pa.goodCallSpace) {
      callDirection += 7;
    }
    if (pa.goodPutSpace) {
      putDirection += 7;
    }

    // ----------------------------------------------------------
    // INDICADORES: 20 puntos
    // Ahora son confirmación, no condición absoluta.
    // ----------------------------------------------------------
    if (ema20 > ema50) {
      callDirection += 7;
      callReasons.add('EMA20 confirma tendencia alcista');
    } else if (ema20 < ema50) {
      putDirection += 7;
      putReasons.add('EMA20 confirma tendencia bajista');
    }

    if (emaSlope > 0) {
      callDirection += 4;
    } else if (emaSlope < 0) {
      putDirection += 4;
    }

    if (macd['macd']! > macd['signal']!) {
      callDirection += 5;
      callReasons.add('MACD confirma momentum alcista');
    } else if (macd['macd']! < macd['signal']!) {
      putDirection += 5;
      putReasons.add('MACD confirma momentum bajista');
    }

    // RSI solamente confirma si está en una zona razonable.
    if (rsi >= 42 && rsi <= 70) {
      callDirection += 2;
    }
    if (rsi >= 30 && rsi <= 58) {
      putDirection += 2;
    }

    // ADX aporta contexto, pero nunca bloquea por sí solo.
    final adxMin = timeframe == '1m'
        ? 14.0
        : timeframe == '2m'
            ? 15.0
            : timeframe == '5m'
                ? 17.0
                : 19.0;
    if (adx >= adxMin) {
      if (callPriceAction >= putPriceAction) {
        callDirection += 2;
      }
      if (putPriceAction > callPriceAction) {
        putDirection += 2;
      }
    }

    // ----------------------------------------------------------
    // TIMEFRAME SUPERIOR: confirmación suave.
    // Una fuerte configuración de Price Action puede operar contra
    // un TF superior neutral o ligeramente contrario.
    // ----------------------------------------------------------
    if (higherTrend == 'ALCISTA') {
      callDirection += 5;
      callReasons.add('TF superior alcista');
    } else if (higherTrend == 'BAJISTA') {
      putDirection += 5;
      putReasons.add('TF superior bajista');
    }

    callDirection = min(callDirection + callPriceAction, 100);
    putDirection = min(putDirection + putPriceAction, 100);

    // ----------------------------------------------------------
    // SETUP: también prioriza Price Action.
    // ----------------------------------------------------------
    final nearEma = (last.close - ema20).abs() <= atrSafe * 1.00;

    final pullbackCall = (nearEma || pa.nearSupport) &&
        (pa.bullishPullback || pa.bullishRejection || pa.bullishEngulfing) &&
        bullishCandle;
    final pullbackPut = (nearEma || pa.nearResistance) &&
        (pa.bearishPullback || pa.bearishRejection || pa.bearishEngulfing) &&
        bearishCandle;

    final breakoutCall = pa.bullishBos &&
        bullishCandle &&
        (last.close - last.open).abs() >= atrSafe * 0.20;
    final breakoutPut = pa.bearishBos &&
        bearishCandle &&
        (last.close - last.open).abs() >= atrSafe * 0.20;

    final impulseCall = pa.bullishImpulse && bullishCandle;
    final impulsePut = pa.bearishImpulse && bearishCandle;

    final continuationCall = bullishCandle && previousBullish && histogram >= 0;
    final continuationPut = bearishCandle && previousBearish && histogram <= 0;

    int callSetup = callPriceAction;
    int putSetup = putPriceAction;
    String callSetupName = 'WAIT';
    String putSetupName = 'WAIT';

    if (pullbackCall) {
      callSetup += 7;
      callSetupName = 'PULLBACK + RECHAZO';
      callSetupReasons.add('Reacción de precio en zona favorable');
    } else if (breakoutCall) {
      callSetup += 8;
      callSetupName = 'BREAKOUT + CONFIRMACIÓN';
      callSetupReasons.add('Ruptura alcista con confirmación');
    } else if (impulseCall) {
      callSetup += 6;
      callSetupName = 'IMPULSO + CONTINUACIÓN';
      callSetupReasons.add('Impulso alcista');
    } else if (continuationCall) {
      callSetup += 4;
      callSetupName = 'CONTINUACIÓN';
      callSetupReasons.add('Continuación del movimiento');
    } else if (bullishCandle) {
      callSetup += 4;
      callSetupName = 'PREPARANDO CALL';
      callSetupReasons.add('Precio en zona de posible reacción');
    }

    if (pullbackPut) {
      putSetup += 7;
      putSetupName = 'PULLBACK + RECHAZO';
      putSetupReasons.add('Reacción de precio en zona favorable');
    } else if (breakoutPut) {
      putSetup += 8;
      putSetupName = 'BREAKOUT + CONFIRMACIÓN';
      putSetupReasons.add('Ruptura bajista con confirmación');
    } else if (impulsePut) {
      putSetup += 6;
      putSetupName = 'IMPULSO + CONTINUACIÓN';
      putSetupReasons.add('Impulso bajista');
    } else if (continuationPut) {
      putSetup += 4;
      putSetupName = 'CONTINUACIÓN';
      putSetupReasons.add('Continuación del movimiento');
    } else if (bearishCandle) {
      putSetup += 4;
      putSetupName = 'PREPARANDO PUT';
      putSetupReasons.add('Precio en zona de posible reacción');
    }

    // ----------------------------------------------------------
    // BLOQUEOS DUROS: solamente situaciones realmente peligrosas.
    // ----------------------------------------------------------
    final callBlockedByResistance = pa.nearResistance &&
        !pa.nearSupport &&
        !pa.bullishBos &&
        callPriceAction < 16;
    final putBlockedBySupport = pa.nearSupport &&
        !pa.nearResistance &&
        !pa.bearishBos &&
        putPriceAction < 16;

    final extensionLimit = timeframe == '1m'
        ? 0.45
        : timeframe == '2m'
            ? 0.55
            : timeframe == '5m'
                ? 0.85
                : 1.10;
    final extended = ema20 != 0 &&
        ((last.close - ema20).abs() / ema20) * 100 > extensionLimit;

    // Price Action fuerte puede superar una pequeña extensión.
    final strongCallPA = callPriceAction >= 28 || pa.bullishBos;
    final strongPutPA = putPriceAction >= 28 || pa.bearishBos;

    final callExtensionBlocked = extended && !strongCallPA;
    final putExtensionBlocked = extended && !strongPutPA;

    // ----------------------------------------------------------
    // ENTRADA: ya no exige una alineación perfecta de indicadores.
    // ----------------------------------------------------------
    // ==========================================================
    // V4: MÁS SEÑALES, PERO SIEMPRE CON DIRECCIÓN DE PRICE ACTION
    // No exigimos que todos los indicadores estén alineados.
    // La PA debe tener una ventaja mínima y el contexto solo filtra.
    // ==========================================================
    final callDominant = callPriceAction >= putPriceAction + 1 ||
        (callPriceAction == putPriceAction && callDirection > putDirection);
    final putDominant = putPriceAction >= callPriceAction + 1 ||
        (putPriceAction == callPriceAction && putDirection > callDirection);

    final callReady = callDominant &&
        callPriceAction >= 5 &&
        callSetup >= 7 &&
        !callBlockedByResistance &&
        !callExtensionBlocked;

    final putReady = putDominant &&
        putPriceAction >= 5 &&
        putSetup >= 7 &&
        !putBlockedBySupport &&
        !putExtensionBlocked;

    // Una configuración PA muy fuerte puede entrar aunque el TF superior
    // no acompañe completamente. Solo se bloquea una contradicción fuerte
    // cuando la acción del precio también es débil.
    final callHigherConflict = higherTrend == 'BAJISTA' && callPriceAction < 7;
    final putHigherConflict = higherTrend == 'ALCISTA' && putPriceAction < 7;

    String action = 'WAIT';
    String direction = 'WAIT';
    String setup = callDirection >= putDirection ? callSetupName : putSetupName;
    String setupStatus = 'ESPERANDO ENTRADA';
    List<String> reasons = [];

    int score;

    if (callReady && !callHigherConflict && callPriceAction >= putPriceAction) {
      action = 'CALL';
      direction = 'UP';
      final callContext = (callDirection - callPriceAction).clamp(0, 45);
      final callPaScore = ((callPriceAction / 55.0) * 100).clamp(0, 100);
      final callContextScore = ((callContext / 45.0) * 100).clamp(0, 100);
      score = ((callPaScore * 0.70) + (callContextScore * 0.30)).round();
      setup = callSetupName;
      setupStatus = 'ENTRADA AHORA';
      reasons = [...callReasons, ...callSetupReasons];
    } else if (putReady &&
        !putHigherConflict &&
        putPriceAction > callPriceAction) {
      action = 'PUT';
      direction = 'DOWN';
      final putContext = (putDirection - putPriceAction).clamp(0, 45);
      final putPaScore = ((putPriceAction / 55.0) * 100).clamp(0, 100);
      final putContextScore = ((putContext / 45.0) * 100).clamp(0, 100);
      score = ((putPaScore * 0.70) + (putContextScore * 0.30)).round();
      setup = putSetupName;
      setupStatus = 'ENTRADA AHORA';
      reasons = [...putReasons, ...putSetupReasons];
    } else {
      final bullishBias = callDirection >= putDirection;
      final selectedDirection = bullishBias ? callDirection : putDirection;
      final selectedPA = bullishBias ? callPriceAction : putPriceAction;
      final selectedSetup = bullishBias ? callSetup : putSetup;
      final selectedContext = (selectedDirection - selectedPA).clamp(0, 45);
      final selectedPaScore = ((selectedPA / 55.0) * 100).clamp(0, 100);
      final selectedContextScore =
          ((selectedContext / 45.0) * 100).clamp(0, 100);
      score =
          ((selectedPaScore * 0.70) + (selectedContextScore * 0.30)).round();

      if (selectedPA >= 5 && selectedDirection >= 28 && selectedSetup >= 7) {
        direction = bullishBias ? 'UP' : 'DOWN';
        setup = bullishBias ? callSetupName : putSetupName;
        setupStatus = bullishBias ? 'PREPARANDO CALL' : 'PREPARANDO PUT';
        reasons = bullishBias
            ? [...callReasons, ...callSetupReasons]
            : [...putReasons, ...putSetupReasons];
      } else {
        setupStatus = 'SIN SETUP';
        reasons = ['La acción del precio todavía no da una entrada clara'];
      }
    }

    String strength = 'WEAK';
    if (action != 'WAIT') {
      if (score >= 78) {
        strength = 'VERY STRONG';
      } else if (score >= 68) {
        strength = 'STRONG';
      } else {
        strength = 'GOOD';
      }
    } else if (score >= 60) {
      strength = 'FILTERED';
    } else if (score >= 45) {
      strength = 'MODERATE';
    }

    if (extended) {
      reasons.add('Precio alejado de EMA20');
    }
    if (higherTrend != 'NEUTRAL' && higherTrend != trend) {
      reasons.add('TF superior no acompaña completamente');
    }
    if (callBlockedByResistance && callDirection >= putDirection) {
      reasons.add('Resistencia cercana');
    }
    if (putBlockedBySupport && putDirection >= callDirection) {
      reasons.add('Soporte cercano');
    }

    return SignalResult(
      action: action,
      direction: direction,
      strength: strength,
      score: score.clamp(0, 100).toInt(),
      ema20: ema20,
      ema50: ema50,
      rsi: rsi,
      macd: macd['macd']!,
      macdSignal: macd['signal']!,
      adx: adx,
      atr: atr,
      entryPrice: last.close,
      trend: trend,
      higherTrend: higherTrend,
      structure: pa.structure,
      priceAction: pa.pattern,
      levelStatus: action == 'CALL'
          ? (pa.goodCallSpace ? 'ESPACIO OK' : 'RESISTENCIA CERCANA')
          : action == 'PUT'
              ? (pa.goodPutSpace ? 'ESPACIO OK' : 'SOPORTE CERCANO')
              : (pa.nearSupport || pa.nearResistance
                  ? 'NIVEL EN VIGILANCIA'
                  : 'ESPERANDO'),
      setup: setup,
      setupStatus: setupStatus,
      reasons: reasons.take(6).toList(),
      entryTiming: action == 'WAIT'
          ? 'ESPERAR SEÑAL'
          : 'ENTRADA EN LA APERTURA DE LA PRÓXIMA VELA 1M',
      plannedEntryTime: action == 'WAIT' ? null : _nextOneMinuteOpen(),
    );
  }
}

// ============================================================
// MAIN PAGE
// ============================================================

class TradingAnalyzerPage extends StatefulWidget {
  const TradingAnalyzerPage({super.key});

  @override
  State<TradingAnalyzerPage> createState() => _TradingAnalyzerPageState();
}

class _TradingAnalyzerPageState extends State<TradingAnalyzerPage> {
  final List<String> assets = [
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'AUD/USD',
    'USD/CAD',
    'USD/CHF',
    'NZD/USD',
    'EUR/GBP',
    'EUR/JPY',
    'EUR/CHF',
    'EUR/AUD',
    'EUR/CAD',
    'EUR/NZD',
    'GBP/JPY',
    'GBP/CHF',
    'GBP/AUD',
    'GBP/CAD',
    'GBP/NZD',
    'AUD/JPY',
    'AUD/NZD',
    'AUD/CAD',
    'AUD/CHF',
    'CAD/JPY',
    'CAD/CHF',
    'CHF/JPY',
    'NZD/JPY',
    'NZD/CAD',
    'NZD/CHF',
    'USD/SGD',
    'USD/HKD',
    'USD/SEK',
    'USD/NOK',
    'USD/DKK',
    'USD/PLN',
    'USD/CZK',
    'USD/HUF',
    'USD/TRY',
    'USD/ZAR',
    'USD/MXN',
    'USD/BRL',
    'USD/THB',
    'USD/ILS',
    'USD/CNH',
    'EUR/PLN',
    'EUR/TRY',
    'EUR/SEK',
    'EUR/NOK',
    'EUR/DKK',
    'EUR/HUF',
    'EUR/CZK',
    'EUR/ZAR',
    'GBP/SEK',
    'GBP/NOK',
    'GBP/SGD',
    'GBP/ZAR',
    'AUD/SGD',
    'AUD/ZAR',
    'NZD/SGD',
    'NZD/JPY',
    'NZD/SGD',
    'SGD/JPY',
  ];

  // El timeframe seleccionado es el timeframe REAL de análisis.
  // La entrada siempre se ejecuta en la siguiente vela 1M.
  final List<String> timeframes = [
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

  double? currentPrice;
  String? errorMessage;

  bool isAnalyzing = false;
  bool isLive = false;

  HubConnection? hubConnection;

  Timer? priceTimer;
  Timer? countdownTimer;

  Duration? entryCountdown;

  bool entryReady = false;

  @override
  void initState() {
    super.initState();
    _startLiveSystem();
  }

  @override
  void dispose() {
    priceTimer?.cancel();
    countdownTimer?.cancel();
    hubConnection?.stop();

    super.dispose();
  }

  // ==========================================================
  // LIVE SYSTEM
  // ==========================================================

  Future<void> _startLiveSystem() async {
    await _connectSignalR();

    priceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshLivePrice();
    });

    await _refreshLivePrice();
  }

  Future<void> _connectSignalR() async {
    try {
      final connection = HubConnectionBuilder()
          .withUrl('https://biquote.io/hubs/tick')
          .withAutomaticReconnect(
        retryDelays: [2000, 5000, 10000, 20000, 30000],
      ).build();

      hubConnection = connection;

      connection.on('ReceiveTick', (arguments) {
        if (arguments == null || arguments.isEmpty) {
          return;
        }

        final first = arguments.first;

        if (first is Map) {
          final data = Map<String, dynamic>.from(first);

          _processTick(data);
        }
      });

      connection.onreconnected(({String? connectionId}) async {
        await _subscribe();
      });

      connection.onclose(({Exception? error}) {});

      connection.onreconnecting(({Exception? error}) {});

      await connection.start();

      await _subscribe();
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    try {
      if (hubConnection == null) {
        return;
      }

      await hubConnection!.invoke(
        'Subscribe',
        args: <Object>[
          <String>[BiquoteService.normalizeSymbol(selectedAsset)],
        ],
      );
    } catch (_) {}
  }

  // ==========================================================
  // PRECIO REST
  // ==========================================================

  Future<void> _refreshLivePrice() async {
    try {
      final price = await BiquoteService.getCurrentPrice(selectedAsset);

      if (price == null || price <= 0) {
        if (!mounted) {
          return;
        }

        setState(() {
          isLive = false;
        });

        return;
      }

      if (!mounted) {
        return;
      }

      // ------------------------------------------------------
      // PROTECCIÓN CONTRA PRECIO FUERA DE ESCALA
      // ------------------------------------------------------

      if (!_isPriceCompatibleWithCandles(price)) {
        setState(() {
          isLive = false;
        });

        return;
      }

      setState(() {
        currentPrice = price;
        isLive = true;
      });

      _updateCurrentCandle(price);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLive = false;
      });
    }
  }

  // ==========================================================
  // SIGNALR
  // ==========================================================

  void _processTick(Map<String, dynamic> data) {
    double? price;

    if (data['mid'] is num) {
      price = (data['mid'] as num).toDouble();
    } else if (data['bid'] is num && data['ask'] is num) {
      price =
          ((data['bid'] as num).toDouble() + (data['ask'] as num).toDouble()) /
              2.0;
    }

    if (price == null || !price.isFinite || price <= 0) {
      return;
    }

    // --------------------------------------------------------
    // PROTECCIÓN CONTRA TICK DE OTRO ACTIVO / DATO INCORRECTO
    // --------------------------------------------------------

    if (!_isPriceCompatibleWithCandles(price)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      currentPrice = price;
      isLive = true;
    });

    _updateCurrentCandle(price);
  }

  // ==========================================================
  // VALIDAR PRECIO CONTRA HISTÓRICO
  // ==========================================================

  bool _isPriceCompatibleWithCandles(double price) {
    if (!price.isFinite || price <= 0) {
      return false;
    }

    if (candles.isEmpty) {
      return true;
    }

    final valid = candles.where(_validChartCandle).toList();

    if (valid.isEmpty) {
      return true;
    }

    final recent = valid.length > 20 ? valid.sublist(valid.length - 20) : valid;

    double minPrice = recent.first.low;
    double maxPrice = recent.first.high;

    for (final candle in recent) {
      minPrice = min(minPrice, candle.low);
      maxPrice = max(maxPrice, candle.high);
    }

    final range = maxPrice - minPrice;

    // --------------------------------------------------------
    // Permitimos un margen razonable.
    // --------------------------------------------------------

    final margin = max(range * 0.20, maxPrice * 0.002).toDouble();

    return price >= minPrice - margin && price <= maxPrice + margin;
  }

  // ==========================================================
  // UPDATE CURRENT CANDLE
  // ==========================================================

  void _updateCurrentCandle(double price) {
    if (candles.isEmpty) {
      return;
    }

    if (!_isPriceCompatibleWithCandles(price)) {
      return;
    }

    const duration = Duration(minutes: 1);

    final now = DateTime.now();

    final start = _floorTime(now, duration);

    final last = candles.last;

    if (last.time.isAtSameMomentAs(start)) {
      final updated = Candle(
        time: last.time,
        open: last.open,
        high: max(last.high, price).toDouble(),
        low: min(last.low, price).toDouble(),
        close: price,
        isOpen: true,
      );

      final list = [...candles.sublist(0, candles.length - 1), updated];

      if (!mounted) {
        return;
      }

      setState(() {
        candles = list;
      });

      return;
    }

    if (last.time.isBefore(start)) {
      final newCandle = Candle(
        time: start,
        open: price,
        high: price,
        low: price,
        close: price,
        isOpen: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        candles = [...candles, newCandle];
      });
    }
  }

  DateTime _floorTime(DateTime time, Duration duration) {
    final ms = time.millisecondsSinceEpoch;

    final bucket = duration.inMilliseconds;

    return DateTime.fromMillisecondsSinceEpoch((ms ~/ bucket) * bucket);
  }

  // ==========================================================
  // CLOSED CANDLES
  // ==========================================================

  List<Candle> _closedCandles(List<Candle> source) {
    final sorted = [...source]..sort((a, b) => a.time.compareTo(b.time));

    return sorted.where((c) => !c.isOpen).toList();
  }

  // ==========================================================
  // ANALYZE
  // ==========================================================

  Future<void> analyze() async {
    if (isAnalyzing) {
      return;
    }

    countdownTimer?.cancel();
    entryReady = false;

    setState(() {
      isAnalyzing = true;
      errorMessage = null;
      signal = null;
      entryCountdown = null;
    });

    try {
      // ========================================================
      // ANÁLISIS = TIMEFRAME SELECCIONADO
      // ENTRADA = SIEMPRE PRÓXIMA VELA 1M
      // ========================================================
      // El timeframe seleccionado controla las velas que alimentan
      // EMA/RSI/MACD/ADX/Price Action. La entrada, en cambio,
      // siempre se programa para la apertura de la siguiente vela 1M.
      final downloadedAnalysis = await BiquoteService.getCandles(
        selectedAsset,
        selectedTimeframe,
      );

      if (downloadedAnalysis.isEmpty) {
        throw Exception(
          'Biquote devolvió 0 velas para $selectedAsset en $selectedTimeframe.',
        );
      }

      final closedAnalysis = _closedCandles(downloadedAnalysis);
      if (closedAnalysis.length < 60) {
        throw Exception(
          'Biquote devolvió ${closedAnalysis.length} velas cerradas en $selectedTimeframe. Se necesitan al menos 60 para calcular la estrategia.',
        );
      }

      final analysis = closedAnalysis.length > 100
          ? closedAnalysis.sublist(closedAnalysis.length - 100)
          : closedAnalysis;

      // Se obtiene 1M aparte únicamente para calcular el momento de entrada.
      // Esto NO cambia el timeframe de análisis.
      final oneMinute = await BiquoteService.getCandles(selectedAsset, '1m');
      final closedOneMinute = _closedCandles(oneMinute);

      if (closedOneMinute.isEmpty) {
        throw Exception(
          'No se pudo obtener una vela 1M cerrada para calcular la entrada.',
        );
      }

      final candidate = TradingStrategy.analyze(
        analysis,
        selectedTimeframe,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        // El gráfico muestra las velas del timeframe analizado.
        candles = downloadedAnalysis;
        currentPrice = oneMinute.last.close;
        isLive = true;
      });

      if (candidate.action == 'WAIT') {
        setState(() {
          signal = candidate;
          entryReady = false;
          entryCountdown = null;
        });
      } else {
        // La señal se muestra INMEDIATAMENTE.
        // No existe una segunda confirmación que pueda convertirla en WAIT.
        // El contador solo marca cuándo ejecutar la entrada.
        setState(() {
          signal = candidate;
          entryReady = false;
        });
        _startEntryCountdown();
      }

      await _refreshLivePrice();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          isAnalyzing = false;
        });
      }
    }
  }

  // ==========================================================
  // COUNTDOWN
  // ==========================================================

  // ==========================================================
  // CHANGE ASSET
  // ==========================================================

  Future<void> _changeAsset(String? value) async {
    if (value == null) {
      return;
    }

    setState(() {
      selectedAsset = value;
      candles = [];
      signal = null;
      errorMessage = null;
      currentPrice = null;
      isLive = false;
      entryCountdown = null;
      entryReady = false;
    });

    countdownTimer?.cancel();

    await _subscribe();
    await _refreshLivePrice();
  }

  // ==========================================================
  // CHANGE TIMEFRAME
  // ==========================================================

  void _changeTimeframe(String? value) {
    if (value == null || !timeframes.contains(value)) {
      return;
    }

    setState(() {
      // La selección cambia el TIMEFRAME REAL DE ANÁLISIS.
      // La entrada seguirá siendo siempre en la siguiente vela 1M.
      selectedTimeframe = value;
      signal = null;
      errorMessage = null;
      entryCountdown = null;
      currentPrice = null;
      entryReady = false;
    });

    countdownTimer?.cancel();
  }

  String _expirationLabel() {
    switch (selectedTimeframe) {
      case '1m':
        return '1 MIN';
      case '2m':
        return '2 MIN';
      case '5m':
        return '5 MIN';
      case '15m':
        return '15 MIN';
      case '30m':
        return '30 MIN';
      case '1h':
        return '1 HORA';
      case '4h':
        return '4 HORAS';
      case '1d':
        return '1 DÍA';
      default:
        return selectedTimeframe.toUpperCase();
    }
  }

  // ==========================================================
  // FORMAT PRICE
  // ==========================================================

  String _formatPrice(double? price) {
    if (price == null) {
      return '--';
    }

    if (price >= 100) {
      return price.toStringAsFixed(3);
    }

    return price.toStringAsFixed(5);
  }

  String _formatCountdown(Duration? duration) {
    if (duration == null) {
      return '--:--';
    }

    final seconds = max(duration.inSeconds, 0);

    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: const Text(
          'Trading Analyzer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLive ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  isLive ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    color: isLive ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSelectors(),
              const SizedBox(height: 16),
              _buildAnalyzeButton(),
              const SizedBox(height: 16),
              if (errorMessage != null) _buildErrorCard(),
              if (signal != null) ...[
                _buildSignalCard(),
                const SizedBox(height: 12),
                _buildEntryCard(),
                const SizedBox(height: 12),
                _buildPriceCard(),
                const SizedBox(height: 12),
                _buildIndicatorsCard(),
                const SizedBox(height: 12),
                _buildPriceActionCard(),
                const SizedBox(height: 16),
                _buildChart(),
              ],
              if (signal == null && errorMessage == null) _buildEmptyState(),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // SELECTORS
  // ==========================================================

  Widget _buildSelectors() {
    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            title: 'ACTIVO',
            value: selectedAsset,
            items: assets,
            onChanged: _changeAsset,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDropdown(
            title: 'TIMEFRAME',
            value: selectedTimeframe,
            items: timeframes,
            onChanged: _changeTimeframe,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String title,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          dropdownColor: const Color(0xFF121A2D),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF121A2D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ==========================================================
  // ANALYZE BUTTON
  // ==========================================================

  Widget _buildAnalyzeButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isAnalyzing ? null : analyze,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isAnalyzing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'ANALIZAR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF25141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SIGNAL CARD
  // ==========================================================

  Widget _buildSignalCard() {
    final s = signal!;

    final Color color = s.action == 'CALL'
        ? Colors.greenAccent
        : s.action == 'PUT'
            ? Colors.redAccent
            : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text(
            'SEÑAL',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.action == 'WAIT' ? 'ESPERAR' : s.action,
            style: TextStyle(
              color: color,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.action == 'WAIT'
                ? 'Sin confirmación suficiente'
                : s.direction == 'UP'
                    ? 'ALZA'
                    : 'BAJA',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Score ${s.score}/100 • ${s.strength}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            s.action == 'WAIT'
                ? s.setupStatus
                : '${s.setup} • ${s.entryTiming} • EXPIRACIÓN ${_expirationLabel()}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ENTRY
  // ==========================================================

  Widget _buildEntryCard() {
    final s = signal!;
    final hasSignal = s.action == 'CALL' || s.action == 'PUT';
    final Color statusColor = s.action == 'CALL'
        ? Colors.greenAccent
        : s.action == 'PUT'
            ? Colors.redAccent
            : Colors.white70;

    final title = s.action == 'CALL'
        ? (entryReady ? 'ENTRAR CALL AHORA' : 'CALL — SEÑAL ACTIVA')
        : s.action == 'PUT'
            ? (entryReady ? 'ENTRAR PUT AHORA' : 'PUT — SEÑAL ACTIVA')
            : 'SIN ENTRADA';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        const Text(
          'PUNTO DE ENTRADA',
          style: TextStyle(
              color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (hasSignal && entryCountdown != null) ...[
          Text(
            entryReady ? '00:00' : _formatCountdown(entryCountdown),
            style: TextStyle(
              color: entryReady ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entryReady ? 'MOMENTO DE ENTRADA' : 'ENTRAR AL LLEGAR A 00:00',
            style: TextStyle(
              color: entryReady ? Colors.greenAccent : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: statusColor, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          s.action == 'CALL'
              ? (entryReady
                  ? 'La siguiente vela 1M está comenzando. Ejecuta CALL manualmente ahora.'
                  : 'Señal CALL detectada. Espera la apertura de la siguiente vela 1M.')
              : s.action == 'PUT'
                  ? (entryReady
                      ? 'La siguiente vela 1M está comenzando. Ejecuta PUT manualmente ahora.'
                      : 'Señal PUT detectada. Espera la apertura de la siguiente vela 1M.')
                  : s.setupStatus,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        if (hasSignal) ...[
          const SizedBox(height: 8),
          Text(
            'Entrada: apertura de la siguiente vela 1M • Expiración: ${_expirationLabel()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ]),
    );
  }

  // ==========================================================
  // ENTRY COUNTDOWN
  // ==========================================================

  // El contador SIEMPRE es de 1 minuto porque la entrada siempre
  // se realiza en la apertura de la siguiente vela 1M.
  //
  // Si la señal se detecta a las 10:05:23,
  // la siguiente vela 1M comienza a las 10:06:00.
  // La entrada se hace exactamente en esa apertura.
  void _startEntryCountdown() {
    countdownTimer?.cancel();
    entryReady = false;

    // SIEMPRE: entrada en la APERTURA de la siguiente vela 1M.
    // Ejemplo: si analizamos a las 10:05:23, la entrada será 10:06:00.
    final now = DateTime.now();
    final currentMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final plannedEntry = currentMinute.add(const Duration(minutes: 1));

    void updateCountdown() {
      if (!mounted || signal == null || signal!.action == 'WAIT') {
        countdownTimer?.cancel();
        return;
      }

      final left = plannedEntry.difference(DateTime.now());
      final seconds = max(0, left.inSeconds);

      setState(() {
        entryCountdown = Duration(seconds: seconds);
        entryReady = seconds <= 0;
      });

      if (seconds <= 0) {
        countdownTimer?.cancel();
      }
    }

    updateCountdown();

    if (plannedEntry.isAfter(DateTime.now())) {
      countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => updateCountdown(),
      );
    }
  }

  // ==========================================================
  // PRICE
  // ==========================================================

  Widget _buildPriceCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'PRECIO',
              style: TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: Text(
              _formatPrice(currentPrice),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // INDICATORS
  // ==========================================================

  Widget _buildIndicatorsCard() {
    final s = signal!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INDICADORES',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          _indicatorRow('EMA 20', s.ema20.toStringAsFixed(5)),
          _indicatorRow('EMA 50', s.ema50.toStringAsFixed(5)),
          _indicatorRow('RSI', s.rsi.toStringAsFixed(2)),
          _indicatorRow('MACD', s.macd.toStringAsFixed(6)),
          _indicatorRow('SIGNAL', s.macdSignal.toStringAsFixed(6)),
          _indicatorRow('ADX', s.adx.toStringAsFixed(2)),
          _indicatorRow('ATR', s.atr.toStringAsFixed(6)),
        ],
      ),
    );
  }

  Widget _indicatorRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceActionCard() {
    final s = signal!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PRICE ACTION + CONFIRMACIÓN',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _indicatorRow('Tendencia', s.trend),
          _indicatorRow('TF superior', s.higherTrend),
          _indicatorRow('Estructura', s.structure),
          _indicatorRow('Patrón', s.priceAction),
          _indicatorRow('Niveles', s.levelStatus),
          _indicatorRow('Setup', s.setup),
          _indicatorRow('Estado', s.setupStatus),
          const SizedBox(height: 10),
          const Text('Motivos',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...s.reasons.map((reason) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $reason',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              )),
        ],
      ),
    );
  }

  // ==========================================================
  // CANDLE CHART
  // ==========================================================

  Widget _buildChart() {
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }

    // --------------------------------------------------------
    // 1. ORDENAR
    // --------------------------------------------------------

    final sorted = [...candles]..sort((a, b) => a.time.compareTo(b.time));

    // --------------------------------------------------------
    // 2. ELIMINAR DUPLICADOS
    // --------------------------------------------------------

    final Map<int, Candle> unique = {};

    for (final candle in sorted) {
      if (!_validChartCandle(candle)) {
        continue;
      }

      unique[candle.time.millisecondsSinceEpoch] = candle;
    }

    final clean = unique.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (clean.isEmpty) {
      return const SizedBox.shrink();
    }

    // --------------------------------------------------------
    // 3. SOLO ÚLTIMAS 60
    // --------------------------------------------------------

    final data = clean.length > 60 ? clean.sublist(clean.length - 60) : clean;

    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    // --------------------------------------------------------
    // 4. CALCULAR RANGO REAL DE PRECIOS
    // --------------------------------------------------------

    double minPrice = data.first.low;
    double maxPrice = data.first.high;

    for (final candle in data) {
      minPrice = min(minPrice, candle.low);

      maxPrice = max(maxPrice, candle.high);
    }

    final priceRange = maxPrice - minPrice;

    // --------------------------------------------------------
    // Evitar que el gráfico quede pegado arriba/abajo.
    // --------------------------------------------------------

    final safeRange = priceRange > 0 ? priceRange : maxPrice * 0.0001;

    final padding = max(safeRange * 0.12, maxPrice * 0.00005).toDouble();

    final axisMin = minPrice - padding;

    final axisMax = maxPrice + padding;

    // --------------------------------------------------------
    // 5. CHART
    // --------------------------------------------------------

    return Container(
      width: double.infinity,
      height: 340,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SfCartesianChart(
        backgroundColor: Colors.transparent,

        margin: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),

        // ----------------------------------------------------
        // X AXIS
        // ----------------------------------------------------
        primaryXAxis: DateTimeAxis(
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(color: Colors.white24),
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
          edgeLabelPlacement: EdgeLabelPlacement.shift,
          intervalType: DateTimeIntervalType.auto,
        ),

        // ----------------------------------------------------
        // Y AXIS
        //
        // AHORA queda FIJADO al precio real.
        // ----------------------------------------------------
        primaryYAxis: NumericAxis(
          opposedPosition: true,
          minimum: axisMin,
          maximum: axisMax,
          majorGridLines: const MajorGridLines(color: Colors.white10, width: 1),
          axisLine: const AxisLine(color: Colors.white24),
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
          decimalPlaces: 5,
          numberFormat: null,
        ),

        tooltipBehavior: TooltipBehavior(enable: true),

        zoomPanBehavior: ZoomPanBehavior(
          enablePanning: true,
          enablePinching: true,
          zoomMode: ZoomMode.x,
        ),

        // ----------------------------------------------------
        // CANDLE SERIES
        // ----------------------------------------------------
        series: <CartesianSeries>[
          CandleSeries<Candle, DateTime>(
            dataSource: data,
            xValueMapper: (Candle c, _) => c.time,
            openValueMapper: (Candle c, _) => c.open,
            highValueMapper: (Candle c, _) => c.high,
            lowValueMapper: (Candle c, _) => c.low,
            closeValueMapper: (Candle c, _) => c.close,
            enableSolidCandles: true,
            bullColor: Colors.greenAccent,
            bearColor: Colors.redAccent,
            borderWidth: 1.2,
            spacing: 0.05,
            width: 0.85,
            emptyPointSettings: const EmptyPointSettings(
              mode: EmptyPointMode.drop,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // VALID CHART CANDLE
  // ==========================================================

  bool _validChartCandle(Candle c) {
    if (!c.open.isFinite ||
        !c.high.isFinite ||
        !c.low.isFinite ||
        !c.close.isFinite) {
      return false;
    }

    if (c.open <= 0 || c.high <= 0 || c.low <= 0 || c.close <= 0) {
      return false;
    }

    final high = max(c.open, c.close).toDouble();

    final low = min(c.open, c.close).toDouble();

    if (c.high < high) {
      return false;
    }

    if (c.low > low) {
      return false;
    }

    // --------------------------------------------------------
    // EVITAR VELAS EXTREMADAMENTE ANÓMALAS
    // --------------------------------------------------------

    final range = c.high - c.low;

    final reference = max(c.open, c.close);

    if (reference <= 0) {
      return false;
    }

    // Una vela cuyo rango sea más del 5% de su precio
    // se considera sospechosa para Forex.
    //
    // Esto evita que un dato roto destruya la escala
    // del gráfico.
    if (range / reference > 0.05) {
      return false;
    }

    return true;
  }

  // ==========================================================
  // EMPTY
  // ==========================================================

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.analytics_outlined, size: 42, color: Colors.white30),
          SizedBox(height: 12),
          Text(
            'Analiza un activo para obtener una señal',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// APP
// ============================================================

class TradingAnalyzerApp extends StatelessWidget {
  const TradingAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Analyzer',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      home: const TradingAnalyzerPage(),
    );
  }
}

// ============================================================
// MAIN
// ============================================================

void main() {
  runApp(const TradingAnalyzerApp());
}
