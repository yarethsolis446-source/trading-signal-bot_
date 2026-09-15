
"""
BACKTEST GRANDE - TRADING SIGNAL BOT
====================================

Fuente histórica:
    HistData - Forex M1

IMPORTANTE:
    Biquote se mantiene para el BOT EN TIEMPO REAL.
    Este script usa datos históricos M1 independientes para backtesting.

Pares:
    EURUSD
    GBPUSD
    USDJPY

Expiraciones:
    1, 2, 3, 5, 10, 15 minutos

Estrategia:
    PRICE ACTION DOMINANTE
    + estructura de mercado
    + patrones de velas
    + momentum
    + EMA / RSI / MACD / ADX como confirmación

El script:
    1. Busca archivos históricos locales.
    2. Lee CSV/ZIP de HistData.
    3. Normaliza las velas.
    4. Comprueba cobertura y huecos.
    5. Calcula indicadores.
    6. Detecta Price Action.
    7. Genera señales.
    8. Simula las expiraciones.
    9. Calcula estadísticas.
    10. Guarda CSV y JSON.

Carpeta esperada:

backend/
    backtest_grande.py

    historical_data/
        EURUSD/
            *.zip
            *.csv
        GBPUSD/
            *.zip
            *.csv
        USDJPY/
            *.zip
            *.csv

También acepta directamente:
    historical_data/EURUSD/*.zip
    historical_data/GBPUSD/*.zip
    historical_data/USDJPY/*.zip

NO necesitas instalar TA-Lib.
"""

from __future__ import annotations

import io
import json
import math
import re
import zipfile
from pathlib import Path
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd


# ============================================================
# CONFIGURACIÓN
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

DATA_DIR = BASE_DIR / "historical_data"
OUTPUT_DIR = BASE_DIR / "backtest_grande_data"

PAIRS = {
    "EURUSD": "EURUSD",
    "GBPUSD": "GBPUSD",
    "USDJPY": "USDJPY",
}

EXPIRATIONS = [1, 2, 3, 5, 10, 15]

# Cambia esto si quieres probar más o menos días.
BACKTEST_DAYS = 30

# Mínimo de velas para considerar un dataset utilizable.
MIN_CANDLES = 10_000

# No aceptamos un hueco superior a esto sin reportarlo.
MAX_ACCEPTABLE_GAP_MINUTES = 10

# ============================================================
# ESTRATEGIA
# ============================================================

# Price Action es deliberadamente dominante.
PA_WEIGHT = 0.62
CONTEXT_WEIGHT = 0.38

# Umbral mínimo para lanzar señal.
MIN_TOTAL_SCORE = 52

# Diferencia mínima entre CALL y PUT.
MIN_LEAD = 8

# Si hay conflicto fuerte de Price Action, WAIT.
PA_CONFLICT_PENALTY = 18

# Evita señales absurdas en condiciones extremas.
RSI_OVERBOUGHT = 75
RSI_OVERSOLD = 25


# ============================================================
# UTILIDADES
# ============================================================

def log(msg: str = ""):
    print(msg, flush=True)


def ensure_dirs():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def safe_float(value):
    try:
        if value is None:
            return np.nan

        text = str(value).strip()

        if text == "":
            return np.nan

        text = text.replace(",", ".")

        return float(text)

    except Exception:
        return np.nan


def clean_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    df.columns = [
        str(c).strip().lower()
        .replace(" ", "")
        .replace("-", "")
        .replace("/", "")
        for c in df.columns
    ]

    return df


def find_column(columns, candidates):
    columns = list(columns)

    for candidate in candidates:
        candidate = candidate.lower().replace(" ", "")

        for col in columns:
            if col.lower().replace(" ", "") == candidate:
                return col

    return None


# ============================================================
# LECTURA DE HISTDATA
# ============================================================

def parse_datetime_series(series: pd.Series) -> pd.Series:
    """
    HistData Generic ASCII suele venir como:

        20260901 000001

    o:

        20260901 000001;1.234;1.235;...

    También soportamos formatos ISO.
    """

    s = series.astype(str).str.strip()

    # Formato YYYYMMDD HHMMSS
    dt = pd.to_datetime(
        s,
        format="%Y%m%d %H%M%S",
        errors="coerce",
        utc=True,
    )

    # Segundo intento
    missing = dt.isna()

    if missing.any():
        dt2 = pd.to_datetime(
            s[missing],
            errors="coerce",
            utc=True,
        )

        dt.loc[missing] = dt2

    return dt


def parse_generic_histdata_text(text: str) -> pd.DataFrame:
    """
    Parser flexible para HistData Generic ASCII.

    Formato habitual:

    YYYYMMDD HHMMSS;OPEN;HIGH;LOW;CLOSE;VOLUME
    """

    raw = io.StringIO(text)

    # Detectamos automáticamente ; , tab
    first_lines = text.splitlines()[:10]

    separator = ";"

    if first_lines:
        sample = "\n".join(first_lines)

        if ";" in sample:
            separator = ";"
        elif "\t" in sample:
            separator = "\t"
        elif "," in sample:
            separator = ","

    df = pd.read_csv(
        raw,
        sep=separator,
        header=None,
        engine="python",
    )

    # Eliminamos columnas completamente vacías.
    df = df.dropna(axis=1, how="all")

    if df.shape[1] < 5:
        raise ValueError(
            f"Formato histórico no reconocido. "
            f"Columnas encontradas: {df.shape[1]}"
        )

    # HistData normalmente:
    # datetime, open, high, low, close, volume

    df = df.iloc[:, :6].copy()

    names = [
        "datetime",
        "open",
        "high",
        "low",
        "close",
        "volume",
    ]

    df.columns = names[:df.shape[1]]

    df["datetime"] = parse_datetime_series(df["datetime"])

    for col in ["open", "high", "low", "close"]:
        df[col] = df[col].map(safe_float)

    if "volume" not in df.columns:
        df["volume"] = 0

    df["volume"] = df["volume"].map(safe_float)

    return df


def parse_csv_file(path: Path) -> pd.DataFrame:
    """
    Intenta leer un CSV de HistData o un CSV convencional.
    """

    # Primero intentamos autodetección.
    try:
        df = pd.read_csv(
            path,
            sep=None,
            engine="python",
        )

        df = clean_columns(df)

        # Buscar columnas nombradas.
        time_col = find_column(
            df.columns,
            [
                "datetime",
                "timestamp",
                "date",
                "time",
            ],
        )

        open_col = find_column(df.columns, ["open", "o"])
        high_col = find_column(df.columns, ["high", "h"])
        low_col = find_column(df.columns, ["low", "l"])
        close_col = find_column(df.columns, ["close", "c"])

        if (
            time_col is not None
            and open_col is not None
            and high_col is not None
            and low_col is not None
            and close_col is not None
        ):
            out = pd.DataFrame(
                {
                    "datetime": parse_datetime_series(df[time_col]),
                    "open": df[open_col].map(safe_float),
                    "high": df[high_col].map(safe_float),
                    "low": df[low_col].map(safe_float),
                    "close": df[close_col].map(safe_float),
                }
            )

            volume_col = find_column(
                df.columns,
                ["volume", "vol"],
            )

            if volume_col:
                out["volume"] = df[volume_col].map(safe_float)
            else:
                out["volume"] = 0

            return out

    except Exception:
        pass

    # Si no funcionó, leemos como HistData ASCII.
    text = path.read_text(
        encoding="utf-8",
        errors="ignore",
    )

    return parse_generic_histdata_text(text)


def read_zip(path: Path) -> list[pd.DataFrame]:
    frames = []

    with zipfile.ZipFile(path, "r") as z:
        for name in z.namelist():

            if name.endswith("/"):
                continue

            lower = name.lower()

            if not (
                lower.endswith(".csv")
                or lower.endswith(".txt")
            ):
                continue

            try:
                raw = z.read(name)

                text = raw.decode(
                    "utf-8",
                    errors="ignore",
                )

                df = parse_generic_histdata_text(text)

                if len(df) > 0:
                    frames.append(df)

            except Exception as exc:
                log(
                    f"  [WARN] No se pudo leer {name}: {exc}"
                )

    return frames


def load_pair_files(pair: str) -> pd.DataFrame:
    pair_dir = DATA_DIR / pair

    if not pair_dir.exists():
        raise FileNotFoundError(
            f"No existe la carpeta:\n{pair_dir}\n\n"
            f"Crea esa carpeta y coloca ahí los archivos "
            f"históricos M1 de {pair}."
        )

    files = sorted(
        list(pair_dir.glob("*.csv"))
        + list(pair_dir.glob("*.txt"))
        + list(pair_dir.glob("*.zip"))
    )

    if not files:
        raise FileNotFoundError(
            f"No encontré archivos históricos para {pair} en:\n"
            f"{pair_dir}"
        )

    log(f"\n[{pair}] Archivos encontrados: {len(files)}")

    frames = []

    for path in files:
        log(f"  Leyendo: {path.name}")

        try:
            if path.suffix.lower() == ".zip":
                loaded = read_zip(path)
                frames.extend(loaded)
            else:
                frames.append(parse_csv_file(path))

        except Exception as exc:
            log(
                f"  [WARN] Error leyendo {path.name}: {exc}"
            )

    if not frames:
        raise RuntimeError(
            f"No se pudo leer ningún dato válido para {pair}."
        )

    df = pd.concat(
        frames,
        ignore_index=True,
    )

    df = normalize_dataframe(df)

    return df


def normalize_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    required = [
        "datetime",
        "open",
        "high",
        "low",
        "close",
    ]

    for col in required:
        if col not in df.columns:
            raise ValueError(
                f"Falta columna obligatoria: {col}"
            )

    df["datetime"] = pd.to_datetime(
        df["datetime"],
        errors="coerce",
        utc=True,
    )

    for col in [
        "open",
        "high",
        "low",
        "close",
    ]:
        df[col] = pd.to_numeric(
            df[col],
            errors="coerce",
        )

    if "volume" not in df.columns:
        df["volume"] = 0

    df["volume"] = pd.to_numeric(
        df["volume"],
        errors="coerce",
    ).fillna(0)

    df = df.dropna(
        subset=[
            "datetime",
            "open",
            "high",
            "low",
            "close",
        ]
    )

    # Eliminar precios inválidos.
    df = df[
        (df["open"] > 0)
        & (df["high"] > 0)
        & (df["low"] > 0)
        & (df["close"] > 0)
    ]

    # Orden cronológico.
    df = df.sort_values(
        "datetime"
    )

    # Una sola vela por minuto.
    df["minute"] = df["datetime"].dt.floor("min")

    df = (
        df.groupby("minute", as_index=False)
        .agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
            }
        )
        .rename(
            columns={
                "minute": "datetime"
            }
        )
    )

    df = df.sort_values(
        "datetime"
    ).reset_index(drop=True)

    return df


# ============================================================
# CALIDAD DEL DATASET
# ============================================================

def inspect_data_quality(
    df: pd.DataFrame,
    pair: str,
) -> dict:

    if df.empty:
        return {
            "pair": pair,
            "candles": 0,
            "valid": False,
        }

    diffs = (
        df["datetime"]
        .diff()
        .dt.total_seconds()
        / 60
    )

    gaps = diffs[
        diffs > MAX_ACCEPTABLE_GAP_MINUTES
    ]

    coverage_start = df["datetime"].iloc[0]
    coverage_end = df["datetime"].iloc[-1]

    total_minutes = (
        coverage_end - coverage_start
    ).total_seconds() / 60

    expected = max(
        1,
        int(total_minutes) + 1,
    )

    actual = len(df)

    coverage_ratio = (
        actual / expected
        if expected > 0
        else 0
    )

    largest_gap = (
        float(gaps.max())
        if len(gaps)
        else 0
    )

    return {
        "pair": pair,
        "candles": int(actual),
        "start": coverage_start.isoformat(),
        "end": coverage_end.isoformat(),
        "calendar_minutes": int(total_minutes),
        "coverage_ratio": round(
            coverage_ratio * 100,
            2,
        ),
        "large_gaps": int(len(gaps)),
        "largest_gap_minutes": largest_gap,
        "valid": (
            actual >= MIN_CANDLES
            and coverage_ratio >= 0.90
        ),
    }


# ============================================================
# INDICADORES
# ============================================================

def ema(series, period):
    return series.ewm(
        span=period,
        adjust=False,
    ).mean()


def rsi(series, period=14):
    delta = series.diff()

    gain = delta.clip(
        lower=0
    )

    loss = -delta.clip(
        upper=0
    )

    avg_gain = gain.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    avg_loss = loss.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    rs = avg_gain / avg_loss.replace(
        0,
        np.nan,
    )

    result = 100 - (
        100 / (1 + rs)
    )

    return result


def atr(df, period=14):
    prev_close = df["close"].shift(1)

    tr1 = (
        df["high"]
        - df["low"]
    )

    tr2 = (
        df["high"]
        - prev_close
    ).abs()

    tr3 = (
        df["low"]
        - prev_close
    ).abs()

    tr = pd.concat(
        [
            tr1,
            tr2,
            tr3,
        ],
        axis=1,
    ).max(axis=1)

    return tr.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()


def adx(df, period=14):
    high = df["high"]
    low = df["low"]
    close = df["close"]

    up_move = high.diff()

    down_move = -low.diff()

    plus_dm = pd.Series(
        np.where(
            (up_move > down_move)
            & (up_move > 0),
            up_move,
            0,
        ),
        index=df.index,
    )

    minus_dm = pd.Series(
        np.where(
            (down_move > up_move)
            & (down_move > 0),
            down_move,
            0,
        ),
        index=df.index,
    )

    prev_close = close.shift(1)

    tr = pd.concat(
        [
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)

    atr_value = tr.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()

    plus_di = (
        100
        * plus_dm.ewm(
            alpha=1 / period,
            adjust=False,
            min_periods=period,
        ).mean()
        / atr_value
    )

    minus_di = (
        100
        * minus_dm.ewm(
            alpha=1 / period,
            adjust=False,
            min_periods=period,
        ).mean()
        / atr_value
    )

    denominator = (
        plus_di + minus_di
    ).replace(0, np.nan)

    dx = (
        100
        * (plus_di - minus_di).abs()
        / denominator
    )

    return dx.ewm(
        alpha=1 / period,
        adjust=False,
        min_periods=period,
    ).mean()


def calculate_indicators(df):
    df = df.copy()

    df["ema20"] = ema(
        df["close"],
        20,
    )

    df["ema50"] = ema(
        df["close"],
        50,
    )

    df["rsi14"] = rsi(
        df["close"],
        14,
    )

    ema12 = ema(
        df["close"],
        12,
    )

    ema26 = ema(
        df["close"],
        26,
    )

    df["macd"] = (
        ema12 - ema26
    )

    df["macd_signal"] = ema(
        df["macd"],
        9,
    )

    df["atr14"] = atr(
        df,
        14,
    )

    df["adx14"] = adx(
        df,
        14,
    )

    return df


# ============================================================
# PRICE ACTION
# ============================================================

def candle_stats(row):
    body = abs(
        row["close"]
        - row["open"]
    )

    total_range = (
        row["high"]
        - row["low"]
    )

    if total_range <= 0:
        return {
            "body": 0,
            "range": 0,
            "upper": 0,
            "lower": 0,
        }

    upper = (
        row["high"]
        - max(
            row["open"],
            row["close"],
        )
    )

    lower = (
        min(
            row["open"],
            row["close"],
        )
        - row["low"]
    )

    return {
        "body": body,
        "range": total_range,
        "upper": upper,
        "lower": lower,
    }


def detect_price_action(df, i):
    if i < 5:
        return {
            "bull": 0,
            "bear": 0,
            "patterns": [],
            "structure": "NONE",
        }

    row = df.iloc[i]
    prev = df.iloc[i - 1]

    s = candle_stats(row)
    ps = candle_stats(prev)

    bull = 0
    bear = 0

    patterns = []

    # --------------------------------------------------------
    # Candle direction
    # --------------------------------------------------------

    if row["close"] > row["open"]:
        bull += 4
        patterns.append("BULLISH_CANDLE")

    elif row["close"] < row["open"]:
        bear += 4
        patterns.append("BEARISH_CANDLE")

    # --------------------------------------------------------
    # Bullish engulfing
    # --------------------------------------------------------

    bullish_engulfing = (
        prev["close"] < prev["open"]
        and row["close"] > row["open"]
        and row["open"] <= prev["close"]
        and row["close"] >= prev["open"]
    )

    if bullish_engulfing:
        bull += 15
        patterns.append(
            "BULLISH_ENGULFING"
        )

    # --------------------------------------------------------
    # Bearish engulfing
    # --------------------------------------------------------

    bearish_engulfing = (
        prev["close"] > prev["open"]
        and row["close"] < row["open"]
        and row["open"] >= prev["close"]
        and row["close"] <= prev["open"]
    )

    if bearish_engulfing:
        bear += 15
        patterns.append(
            "BEARISH_ENGULFING"
        )

    # --------------------------------------------------------
    # Bullish rejection
    # --------------------------------------------------------

    bullish_rejection = (
        s["range"] > 0
        and s["lower"] >= s["body"] * 1.8
        and s["lower"] > s["upper"] * 1.3
        and row["close"] >= row["low"]
            + s["range"] * 0.55
    )

    if bullish_rejection:
        bull += 13
        patterns.append(
            "BULLISH_REJECTION"
        )

    # --------------------------------------------------------
    # Bearish rejection
    # --------------------------------------------------------

    bearish_rejection = (
        s["range"] > 0
        and s["upper"] >= s["body"] * 1.8
        and s["upper"] > s["lower"] * 1.3
        and row["close"] <= row["low"]
            + s["range"] * 0.45
    )

    if bearish_rejection:
        bear += 13
        patterns.append(
            "BEARISH_REJECTION"
        )

    # --------------------------------------------------------
    # Impulse candle
    # --------------------------------------------------------

    if (
        s["range"] > 0
        and s["body"] / s["range"] >= 0.70
    ):
        if row["close"] > row["open"]:
            bull += 12
            patterns.append(
                "BULLISH_IMPULSE"
            )

        elif row["close"] < row["open"]:
            bear += 12
            patterns.append(
                "BEARISH_IMPULSE"
            )

    # --------------------------------------------------------
    # Breakout
    # --------------------------------------------------------

    previous_high = df["high"].iloc[
        max(0, i - 5):i
    ].max()

    previous_low = df["low"].iloc[
        max(0, i - 5):i
    ].min()

    if (
        row["close"] > previous_high
        and row["close"] > row["open"]
    ):
        bull += 12
        patterns.append(
            "BULLISH_BREAKOUT"
        )

    if (
        row["close"] < previous_low
        and row["close"] < row["open"]
    ):
        bear += 12
        patterns.append(
            "BEARISH_BREAKOUT"
        )

    # --------------------------------------------------------
    # Market structure
    # --------------------------------------------------------

    h1 = df["high"].iloc[i - 1]
    h2 = df["high"].iloc[i - 2]

    l1 = df["low"].iloc[i - 1]
    l2 = df["low"].iloc[i - 2]

    if (
        row["high"] > h1 > h2
        and row["low"] > l1 > l2
    ):
        bull += 12
        patterns.append("HH_HL")
        structure = "BULLISH"

    elif (
        row["high"] < h1 < h2
        and row["low"] < l1 < l2
    ):
        bear += 12
        patterns.append("LH_LL")
        structure = "BEARISH"

    else:
        structure = "RANGE"

    return {
        "bull": min(55, bull),
        "bear": min(55, bear),
        "patterns": patterns,
        "structure": structure,
    }


# ============================================================
# CONTEXTO
# ============================================================

def calculate_context(row):
    bull = 0
    bear = 0

    # EMA
    if row["ema20"] > row["ema50"]:
        bull += 8

    elif row["ema20"] < row["ema50"]:
        bear += 8

    # RSI
    if 50 <= row["rsi14"] <= 70:
        bull += 5

    elif 30 <= row["rsi14"] < 50:
        bear += 5

    # MACD
    if row["macd"] > row["macd_signal"]:
        bull += 5

    elif row["macd"] < row["macd_signal"]:
        bear += 5

    # ADX
    if row["adx14"] >= 20:
        if row["ema20"] > row["ema50"]:
            bull += 5

        elif row["ema20"] < row["ema50"]:
            bear += 5

    return {
        "bull": min(23, bull),
        "bear": min(23, bear),
    }


# ============================================================
# SEÑAL
# ============================================================

def generate_signal(df, i):
    row = df.iloc[i]

    pa = detect_price_action(
        df,
        i,
    )

    context = calculate_context(
        row,
    )

    pa_bull = pa["bull"]
    pa_bear = pa["bear"]

    context_bull = context["bull"]
    context_bear = context["bear"]

    # Price Action domina.
    bull_score = (
        pa_bull * PA_WEIGHT
        + context_bull * CONTEXT_WEIGHT
    )

    bear_score = (
        pa_bear * PA_WEIGHT
        + context_bear * CONTEXT_WEIGHT
    )

    # Penalización de conflicto.
    if (
        pa_bull >= 20
        and pa_bear >= 20
    ):
        bull_score -= PA_CONFLICT_PENALTY
        bear_score -= PA_CONFLICT_PENALTY

    rsi_value = row["rsi14"]
    adx_value = row["adx14"]

    # Condiciones extremas.
    if rsi_value >= RSI_OVERBOUGHT:
        bull_score -= 8

    if rsi_value <= RSI_OVERSOLD:
        bear_score -= 8

    lead = abs(
        bull_score - bear_score
    )

    if (
        bull_score >= MIN_TOTAL_SCORE
        and bull_score > bear_score
        and lead >= MIN_LEAD
    ):
        signal = "CALL"

    elif (
        bear_score >= MIN_TOTAL_SCORE
        and bear_score > bull_score
        and lead >= MIN_LEAD
    ):
        signal = "PUT"

    else:
        signal = "WAIT"

    return {
        "signal": signal,
        "bull_score": round(
            bull_score,
            2,
        ),
        "bear_score": round(
            bear_score,
            2,
        ),
        "pa_bull": pa_bull,
        "pa_bear": pa_bear,
        "context_bull": context_bull,
        "context_bear": context_bear,
        "lead": round(
            lead,
            2,
        ),
        "patterns": "|".join(
            pa["patterns"]
        ),
        "structure": pa["structure"],
        "rsi": round(
            float(rsi_value),
            4,
        ),
        "adx": round(
            float(adx_value),
            4,
        ),
    }


# ============================================================
# SIMULACIÓN
# ============================================================

def simulate_trade(
    df,
    signal_index,
    signal,
    expiration,
):
    """
    Señal al cierre de la vela signal_index.

    Entrada:
        apertura de la siguiente vela.

    Expiración:
        cierre de la vela correspondiente
        al número de minutos elegido.

    Ejemplo:
        señal en vela 100
        expiración 5m
        entrada = open[101]
        resultado = close[105]
    """

    entry_index = signal_index + 1
    exit_index = (
        entry_index
        + expiration
        - 1
    )

    if exit_index >= len(df):
        return None

    entry_row = df.iloc[
        entry_index
    ]

    exit_row = df.iloc[
        exit_index
    ]

    entry_price = float(
        entry_row["open"]
    )

    exit_price = float(
        exit_row["close"]
    )

    if signal == "CALL":

        if exit_price > entry_price:
            result = "WIN"

        elif exit_price < entry_price:
            result = "LOSS"

        else:
            result = "DRAW"

    elif signal == "PUT":

        if exit_price < entry_price:
            result = "WIN"

        elif exit_price > entry_price:
            result = "LOSS"

        else:
            result = "DRAW"

    else:
        return None

    return {
        "signal_time": df.iloc[
            signal_index
        ]["datetime"].isoformat(),

        "entry_time": entry_row[
            "datetime"
        ].isoformat(),

        "exit_time": exit_row[
            "datetime"
        ].isoformat(),

        "signal": signal,

        "expiration_minutes": expiration,

        "entry_price": entry_price,

        "exit_price": exit_price,

        "price_change": (
            exit_price
            - entry_price
        ),

        "result": result,
    }


# ============================================================
# BACKTEST DE UN PAR
# ============================================================

def backtest_pair(
    pair,
    df,
):
    log(
        f"\n{'=' * 70}"
    )

    log(
        f"BACKTEST {pair}"
    )

    log(
        f"{'=' * 70}"
    )

    quality = inspect_data_quality(
        df,
        pair,
    )

    log(
        f"Velas: {quality['candles']:,}"
    )

    log(
        f"Desde: {quality.get('start', '-')}"
    )

    log(
        f"Hasta: {quality.get('end', '-')}"
    )

    log(
        f"Cobertura: "
        f"{quality.get('coverage_ratio', 0):.2f}%"
    )

    log(
        f"Huecos grandes: "
        f"{quality.get('large_gaps', 0)}"
    )

    log(
        f"Mayor hueco: "
        f"{quality.get('largest_gap_minutes', 0):.1f} min"
    )

    if not quality["valid"]:
        log(
            "\n[ERROR] Dataset insuficiente "
            "para considerarlo un backtest grande."
        )

        return [], quality

    df = calculate_indicators(
        df
    )

    # Quitamos periodo inicial de indicadores.
    df = df.dropna(
        subset=[
            "ema20",
            "ema50",
            "rsi14",
            "macd",
            "macd_signal",
            "atr14",
            "adx14",
        ]
    ).reset_index(
        drop=True
    )

    operations = []

    # Dejamos margen al final para todas las expiraciones.
    max_exp = max(
        EXPIRATIONS
    )

    end_index = (
        len(df)
        - max_exp
        - 2
    )

    for i in range(
        60,
        end_index,
    ):

        signal_info = generate_signal(
            df,
            i,
        )

        signal = signal_info[
            "signal"
        ]

        if signal not in (
            "CALL",
            "PUT",
        ):
            continue

        for expiration in EXPIRATIONS:

            trade = simulate_trade(
                df,
                i,
                signal,
                expiration,
            )

            if trade is None:
                continue

            trade.update(
                {
                    "pair": pair,
                    "pa_patterns": signal_info[
                        "patterns"
                    ],
                    "structure": signal_info[
                        "structure"
                    ],
                    "bull_score": signal_info[
                        "bull_score"
                    ],
                    "bear_score": signal_info[
                        "bear_score"
                    ],
                    "pa_bull": signal_info[
                        "pa_bull"
                    ],
                    "pa_bear": signal_info[
                        "pa_bear"
                    ],
                    "context_bull": signal_info[
                        "context_bull"
                    ],
                    "context_bear": signal_info[
                        "context_bear"
                    ],
                    "lead": signal_info[
                        "lead"
                    ],
                    "rsi": signal_info[
                        "rsi"
                    ],
                    "adx": signal_info[
                        "adx"
                    ],
                }
            )

            operations.append(
                trade
            )

    log(
        f"Operaciones generadas: "
        f"{len(operations):,}"
    )

    return operations, quality


# ============================================================
# ESTADÍSTICAS
# ============================================================

def stats_from_df(
    df,
    group_cols=None,
):
    if group_cols is None:
        group_cols = []

    if df.empty:
        return pd.DataFrame()

    groups = (
        df.groupby(group_cols)
        if group_cols
        else [(None, df)]
    )

    rows = []

    if group_cols:

        for key, g in groups:

            if not isinstance(
                key,
                tuple,
            ):
                key = (key,)

            row = {}

            for col, value in zip(
                group_cols,
                key,
            ):
                row[col] = value

            rows.append(
                build_stats_row(
                    g,
                    row,
                )
            )

    else:

        rows.append(
            build_stats_row(
                df,
                {},
            )
        )

    return pd.DataFrame(
        rows
    )


def build_stats_row(
    df,
    row,
):
    total = len(df)

    wins = int(
        (df["result"] == "WIN").sum()
    )

    losses = int(
        (df["result"] == "LOSS").sum()
    )

    draws = int(
        (df["result"] == "DRAW").sum()
    )

    decided = wins + losses

    win_rate = (
        wins / decided * 100
        if decided
        else 0
    )

    # Resultado neto hipotético usando
    # +1 por WIN y -1 por LOSS.
    net_units = (
        wins
        - losses
    )

    row.update(
        {
            "operations": total,
            "wins": wins,
            "losses": losses,
            "draws": draws,
            "win_rate_percent": round(
                win_rate,
                2,
            ),
            "net_units": net_units,
        }
    )

    return row


def calculate_streaks(
    results,
):
    max_win = 0
    max_loss = 0

    current_win = 0
    current_loss = 0

    for result in results:

        if result == "WIN":
            current_win += 1
            current_loss = 0
            max_win = max(
                max_win,
                current_win,
            )

        elif result == "LOSS":
            current_loss += 1
            current_win = 0
            max_loss = max(
                max_loss,
                current_loss,
            )

        else:
            current_win = 0
            current_loss = 0

    return max_win, max_loss


# ============================================================
# PRICE ACTION STATS
# ============================================================

def build_price_action_stats(
    operations_df,
):

    rows = []

    if operations_df.empty:
        return pd.DataFrame()

    exploded = (
        operations_df[
            [
                "pa_patterns",
                "result",
            ]
        ]
        .copy()
    )

    exploded["pa_patterns"] = (
        exploded["pa_patterns"]
        .fillna("")
        .str.split("|")
    )

    exploded = exploded.explode(
        "pa_patterns"
    )

    exploded = exploded[
        exploded["pa_patterns"]
        .astype(str)
        .str.len()
        > 0
    ]

    for pattern, group in exploded.groupby(
        "pa_patterns"
    ):

        total = len(group)

        wins = int(
            (
                group["result"]
                == "WIN"
            ).sum()
        )

        losses = int(
            (
                group["result"]
                == "LOSS"
            ).sum()
        )

        decided = wins + losses

        win_rate = (
            wins / decided * 100
            if decided
            else 0
        )

        rows.append(
            {
                "pattern": pattern,
                "operations": total,
                "wins": wins,
                "losses": losses,
                "win_rate_percent": round(
                    win_rate,
                    2,
                ),
            }
        )

    return (
        pd.DataFrame(rows)
        .sort_values(
            [
                "win_rate_percent",
                "operations",
            ],
            ascending=False,
        )
        .reset_index(drop=True)
    )


# ============================================================
# CONSISTENCIA
# ============================================================

def validate_results(
    operations_df,
):
    if operations_df.empty:
        return {
            "valid": False,
            "reason": "Sin operaciones",
        }

    total = len(
        operations_df
    )

    wins = int(
        (
            operations_df["result"]
            == "WIN"
        ).sum()
    )

    losses = int(
        (
            operations_df["result"]
            == "LOSS"
        ).sum()
    )

    draws = int(
        (
            operations_df["result"]
            == "DRAW"
        ).sum()
    )

    if total != (
        wins + losses + draws
    ):
        return {
            "valid": False,
            "reason": "Conteo inconsistente",
        }

    return {
        "valid": True,
        "operations": total,
        "wins": wins,
        "losses": losses,
        "draws": draws,
    }


# ============================================================
# MAIN
# ============================================================

def main():

    ensure_dirs()

    log("")
    log("=" * 78)
    log("       TRADING SIGNAL BOT - BACKTEST GRANDE")
    log("=" * 78)
    log("")
    log(
        "Fuente: HistData M1"
    )
    log(
        "Price Action: DOMINANTE"
    )
    log(
        f"Expiraciones: {EXPIRATIONS}"
    )
    log(
        f"Días objetivo: {BACKTEST_DAYS}"
    )
    log("")

    all_operations = []
    quality_rows = []

    # --------------------------------------------------------
    # Cargar pares
    # --------------------------------------------------------

    for pair in PAIRS:

        try:

            df = load_pair_files(
                pair
            )

            operations, quality = (
                backtest_pair(
                    pair,
                    df,
                )
            )

            quality_rows.append(
                quality
            )

            all_operations.extend(
                operations
            )

        except Exception as exc:

            log("")
            log(
                f"[ERROR] {pair}: {exc}"
            )

            quality_rows.append(
                {
                    "pair": pair,
                    "candles": 0,
                    "valid": False,
                    "error": str(exc),
                }
            )

    # --------------------------------------------------------
    # DataFrame final
    # --------------------------------------------------------

    operations_df = pd.DataFrame(
        all_operations
    )

    if operations_df.empty:

        log("")
        log(
            "=" * 78
        )
        log(
            "NO HAY OPERACIONES"
        )
        log(
            "=" * 78
        )
        log("")
        log(
            "Revisa la carpeta:"
        )
        log(
            str(DATA_DIR)
        )
        log("")
        log(
            "Debes colocar los históricos M1 "
            "de EURUSD, GBPUSD y USDJPY."
        )

        return

    # --------------------------------------------------------
    # Validación
    # --------------------------------------------------------

    validation = validate_results(
        operations_df
    )

    log("")
    log(
        "=" * 78
    )
    log(
        "VALIDACIÓN"
    )
    log(
        "=" * 78
    )

    log(
        f"Resultado válido: "
        f"{validation['valid']}"
    )

    log(
        f"Operaciones únicas: "
        f"{validation['operations']:,}"
    )

    log(
        f"Wins: "
        f"{validation['wins']:,}"
    )

    log(
        f"Losses: "
        f"{validation['losses']:,}"
    )

    log(
        f"Draws: "
        f"{validation['draws']:,}"
    )

    # --------------------------------------------------------
    # Estadísticas
    # --------------------------------------------------------

    global_stats = stats_from_df(
        operations_df
    )

    pair_stats = stats_from_df(
        operations_df,
        ["pair"],
    )

    expiration_stats = stats_from_df(
        operations_df,
        ["expiration_minutes"],
    )

    signal_stats = stats_from_df(
        operations_df,
        ["signal"],
    )

    structure_stats = stats_from_df(
        operations_df,
        ["structure"],
    )

    pa_stats = build_price_action_stats(
        operations_df
    )

    # --------------------------------------------------------
    # Streaks
    # --------------------------------------------------------

    ordered = operations_df.sort_values(
        [
            "pair",
            "expiration_minutes",
            "entry_time",
        ]
    )

    max_win, max_loss = calculate_streaks(
        ordered["result"].tolist()
    )

    # --------------------------------------------------------
    # Imprimir resultados
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "RESULTADO GLOBAL"
    )
    log(
        "=" * 78
    )

    row = global_stats.iloc[0]

    log(
        f"Operaciones: "
        f"{int(row['operations']):,}"
    )

    log(
        f"Wins: "
        f"{int(row['wins']):,}"
    )

    log(
        f"Losses: "
        f"{int(row['losses']):,}"
    )

    log(
        f"Draws: "
        f"{int(row['draws']):,}"
    )

    log(
        f"Win Rate: "
        f"{row['win_rate_percent']:.2f}%"
    )

    log(
        f"Resultado neto hipotético: "
        f"{int(row['net_units']):+,} unidades"
    )

    log(
        f"Mayor racha WIN: "
        f"{max_win}"
    )

    log(
        f"Mayor racha LOSS: "
        f"{max_loss}"
    )

    # --------------------------------------------------------
    # Por expiración
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "POR EXPIRACIÓN"
    )
    log(
        "=" * 78
    )

    if not expiration_stats.empty:

        expiration_stats = (
            expiration_stats.sort_values(
                "win_rate_percent",
                ascending=False,
            )
        )

        print(
            expiration_stats.to_string(
                index=False
            )
        )

    # --------------------------------------------------------
    # Por par
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "POR PAR"
    )
    log(
        "=" * 78
    )

    if not pair_stats.empty:

        pair_stats = (
            pair_stats.sort_values(
                "win_rate_percent",
                ascending=False,
            )
        )

        print(
            pair_stats.to_string(
                index=False
            )
        )

    # --------------------------------------------------------
    # CALL vs PUT
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "CALL VS PUT"
    )
    log(
        "=" * 78
    )

    if not signal_stats.empty:

        print(
            signal_stats.to_string(
                index=False
            )
        )

    # --------------------------------------------------------
    # Price Action
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "PRICE ACTION"
    )
    log(
        "=" * 78
    )

    if not pa_stats.empty:

        print(
            pa_stats.to_string(
                index=False
            )
        )

    # --------------------------------------------------------
    # Estructura
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "ESTRUCTURA"
    )
    log(
        "=" * 78
    )

    if not structure_stats.empty:

        print(
            structure_stats.to_string(
                index=False
            )
        )

    # --------------------------------------------------------
    # Guardar operaciones
    # --------------------------------------------------------

    operations_path = (
        OUTPUT_DIR
        / "backtest_grande_operaciones.csv"
    )

    operations_df.to_csv(
        operations_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Guardar resumen
    # --------------------------------------------------------

    summary_rows = []

    summary_rows.append(
        {
            "scope": "GLOBAL",
            "operations": int(
                row["operations"]
            ),
            "wins": int(
                row["wins"]
            ),
            "losses": int(
                row["losses"]
            ),
            "draws": int(
                row["draws"]
            ),
            "win_rate_percent": float(
                row["win_rate_percent"]
            ),
            "net_units": int(
                row["net_units"]
            ),
            "max_win_streak": max_win,
            "max_loss_streak": max_loss,
        }
    )

    summary_path = (
        OUTPUT_DIR
        / "backtest_grande_resumen.csv"
    )

    pd.DataFrame(
        summary_rows
    ).to_csv(
        summary_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Guardar por expiración
    # --------------------------------------------------------

    expiration_path = (
        OUTPUT_DIR
        / "backtest_grande_expiraciones.csv"
    )

    expiration_stats.to_csv(
        expiration_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Guardar por par
    # --------------------------------------------------------

    pair_path = (
        OUTPUT_DIR
        / "backtest_grande_pares.csv"
    )

    pair_stats.to_csv(
        pair_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Guardar CALL/PUT
    # --------------------------------------------------------

    call_put_path = (
        OUTPUT_DIR
        / "backtest_grande_call_put.csv"
    )

    signal_stats.to_csv(
        call_put_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Guardar Price Action
    # --------------------------------------------------------

    pa_path = (
        OUTPUT_DIR
        / "backtest_grande_price_action.csv"
    )

    pa_stats.to_csv(
        pa_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Calidad de datos
    # --------------------------------------------------------

    quality_path = (
        OUTPUT_DIR
        / "backtest_grande_calidad.csv"
    )

    pd.DataFrame(
        quality_rows
    ).to_csv(
        quality_path,
        index=False,
        encoding="utf-8-sig",
    )

    # --------------------------------------------------------
    # Reporte JSON
    # --------------------------------------------------------

    report = {
        "backtest": {
            "source": "HistData",
            "timeframe": "1m",
            "target_days": BACKTEST_DAYS,
            "pairs": list(
                PAIRS.keys()
            ),
            "expirations": EXPIRATIONS,
            "strategy": {
                "price_action_dominant": True,
                "pa_weight": PA_WEIGHT,
                "context_weight": CONTEXT_WEIGHT,
                "minimum_total_score": MIN_TOTAL_SCORE,
                "minimum_lead": MIN_LEAD,
            },
        },

        "validation": validation,

        "global": {
            "operations": int(
                row["operations"]
            ),
            "wins": int(
                row["wins"]
            ),
            "losses": int(
                row["losses"]
            ),
            "draws": int(
                row["draws"]
            ),
            "win_rate_percent": float(
                row["win_rate_percent"]
            ),
            "net_units": int(
                row["net_units"]
            ),
            "max_win_streak": max_win,
            "max_loss_streak": max_loss,
        },

        "quality": quality_rows,

        "notes": [
            "Los resultados históricos no garantizan resultados futuros.",
            "El backtest utiliza datos históricos de Forex y no datos OTC de Quotex.",
            "La tasa de acierto no representa una probabilidad calibrada.",
            "El resultado económico real depende del payout, ejecución y condiciones del broker.",
        ],
    }

    json_path = (
        OUTPUT_DIR
        / "backtest_grande_reporte.json"
    )

    with open(
        json_path,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            report,
            f,
            indent=2,
            ensure_ascii=False,
        )

    # --------------------------------------------------------
    # Archivos finales
    # --------------------------------------------------------

    log("")
    log(
        "=" * 78
    )
    log(
        "ARCHIVOS GENERADOS"
    )
    log(
        "=" * 78
    )

    log(
        f"Operaciones: {operations_path}"
    )

    log(
        f"Resumen: {summary_path}"
    )

    log(
        f"Expiraciones: {expiration_path}"
    )

    log(
        f"Pares: {pair_path}"
    )

    log(
        f"CALL/PUT: {call_put_path}"
    )

    log(
        f"Price Action: {pa_path}"
    )

    log(
        f"Calidad: {quality_path}"
    )

    log(
        f"Reporte JSON: {json_path}"
    )

    log("")
    log(
        "=" * 78
    )
    log(
        "BACKTEST TERMINADO"
    )
    log(
        "=" * 78
    )
    log("")


if __name__ == "__main__":
    main()

