/**
 * Santa Bárbara Tactical Communications — SIGINT Component
 * Prototype v5 for Ares OS artillery C4ISR.
 *
 * Uses Gemini Live API for real-time audio analysis.
 * System prompt extracts MGRS coordinates, fire calls, tactical keywords,
 * and unit callsigns from live audio in structured JSON format.
 */

import * as React from 'react';
import {
    Box,
    Button,
    Chip,
    Divider,
    IconButton,
    Paper,
    Stack,
    Tooltip,
    Typography,
} from '@mui/material';
import MicIcon from '@mui/icons-material/Mic';
import MicOffIcon from '@mui/icons-material/MicOff';
import SendIcon from '@mui/icons-material/Send';
import DeleteSweepIcon from '@mui/icons-material/DeleteSweep';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const GEMINI_API_URL = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent';

const SIGINT_SYSTEM_PROMPT = `Eres un operador SIGINT experto en comunicaciones militares de artillería. Analiza el audio en tiempo real y extrae: coordenadas MGRS, llamadas de fuego, palabras clave tácticas (Mayday, Troop in contact, adjust fire, fire for effect), e indicativos de unidad. Responde en formato JSON estructurado con campos 'type', 'content', 'confidence'. El campo 'type' debe ser uno de: MGRS_COORD | FIRE_CALL | EMERGENCY | UNIT_ID | GENERAL. El campo 'confidence' debe ser un número entre 0 y 1. Si no detectas información táctica relevante, responde con {"type":"GENERAL","content":"...transcripción...","confidence":0.5}`;

const EMERGENCY_KEYWORDS = ['mayday', 'troop in contact', 'tic', 'man down', 'contact', 'ambush'];
const FIRE_KEYWORDS = ['adjust fire', 'fire for effect', 'ffe', 'splash', 'rounds complete', 'end of mission'];
const MGRS_RE = /\b([0-9]{1,2}[C-X][A-Z]{2}[0-9]{4,10})\b/gi;

// BMS localStorage key
const BMS_STORAGE_KEY = 'santa_barbara_bms_log';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function classifyText(text) {
    const lower = text.toLowerCase();
    if (EMERGENCY_KEYWORDS.some(kw => lower.includes(kw))) return 'EMERGENCY';
    if (FIRE_KEYWORDS.some(kw => lower.includes(kw))) return 'FIRE_CALL';
    const mgrs = text.match(MGRS_RE);
    if (mgrs) return 'MGRS_COORD';
    return 'GENERAL';
}

function parseSigintJson(raw) {
    try {
        const parsed = JSON.parse(raw);
        if (parsed.type && parsed.content !== undefined) return parsed;
    } catch {
        // Gemini may return non-JSON text; classify it locally
    }
    return {
        type: classifyText(raw),
        content: raw,
        confidence: 0.6,
    };
}

function typeColor(type) {
    switch (type) {
        case 'EMERGENCY': return '#FF3D3D';
        case 'FIRE_CALL': return '#FF8C00';
        case 'MGRS_COORD': return '#FFD700';
        case 'UNIT_ID': return '#00E5FF';
        default: return '#B0BEC5';
    }
}

function HighlightedText({ text, type }) {
    const color = typeColor(type);
    // Highlight MGRS coordinates in amber
    const parts = text.split(MGRS_RE);
    return (
        <Typography variant="body2" sx={{ fontFamily: 'monospace', color, lineHeight: 1.6 }}>
            {parts.map((part, i) =>
                MGRS_RE.test(part) ? (
                    <Box key={i} component="span" sx={{ color: '#FFD700', fontWeight: 700, background: 'rgba(255,215,0,0.12)', px: 0.5, borderRadius: 0.5 }}>
                        {part}
                    </Box>
                ) : (
                    <span key={i}>{part}</span>
                )
            )}
        </Typography>
    );
}

// ---------------------------------------------------------------------------
// Main Component
// ---------------------------------------------------------------------------
export default function SantaBarbaraTacticalComms() {
    const [isListening, setIsListening] = React.useState(false);
    const [transcript, setTranscript] = React.useState([]);   // raw transcript lines
    const [intelItems, setIntelItems] = React.useState([]);   // parsed tactical intel
    const [statusMsg, setStatusMsg] = React.useState('Listo. Pulsa el micrófono para iniciar análisis SIGINT.');
    const [apiKey, setApiKey] = React.useState('');

    const wsRef = React.useRef(null);
    const mediaStreamRef = React.useRef(null);
    const audioContextRef = React.useRef(null);
    const processorRef = React.useRef(null);
    const transcriptEndRef = React.useRef(null);
    const intelEndRef = React.useRef(null);

    // Auto-scroll
    React.useEffect(() => { transcriptEndRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [transcript]);
    React.useEffect(() => { intelEndRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [intelItems]);

    // Read Gemini API key from localStorage (set in preferences)
    React.useEffect(() => {
        const stored = localStorage.getItem('gemini_api_key') || '';
        setApiKey(stored);
    }, []);

    // ---------------------------------------------------------------------------
    // WebSocket + Audio pipeline
    // ---------------------------------------------------------------------------
    const startListening = React.useCallback(async () => {
        if (!apiKey) {
            setStatusMsg('Error: configura tu GEMINI_API_KEY en localStorage[gemini_api_key]');
            return;
        }

        try {
            setStatusMsg('Conectando con Gemini Live API...');

            // Open Gemini WebSocket
            const url = `${GEMINI_API_URL}?key=${apiKey}`;
            const ws = new WebSocket(url);
            wsRef.current = ws;

            ws.onopen = () => {
                setStatusMsg('Enlace Gemini activo — enviando configuración SIGINT...');
                // Send setup message with system prompt
                ws.send(JSON.stringify({
                    setup: {
                        model: 'models/gemini-2.0-flash-exp',
                        generation_config: {
                            response_modalities: ['TEXT'],
                        },
                        system_instruction: {
                            parts: [{ text: SIGINT_SYSTEM_PROMPT }],
                        },
                    },
                }));
            };

            ws.onmessage = (event) => {
                try {
                    const msg = JSON.parse(event.data);
                    const parts = msg?.serverContent?.modelTurn?.parts || [];
                    for (const part of parts) {
                        if (part.text) {
                            const raw = part.text.trim();
                            if (!raw) continue;
                            // Add to raw transcript
                            setTranscript(prev => [...prev, { id: Date.now() + Math.random(), text: raw }]);
                            // Parse for tactical intel
                            const intel = parseSigintJson(raw);
                            if (intel.type !== 'GENERAL' || intel.confidence > 0.7) {
                                setIntelItems(prev => [...prev, { ...intel, id: Date.now() + Math.random(), ts: new Date().toISOString() }]);
                            }
                        }
                    }
                } catch {
                    // Ignore malformed messages
                }
            };

            ws.onerror = () => setStatusMsg('Error de WebSocket. Verifica tu API key y conexión.');
            ws.onclose = () => {
                setIsListening(false);
                setStatusMsg('Conexión cerrada.');
            };

            // Microphone capture
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            mediaStreamRef.current = stream;

            const audioCtx = new AudioContext({ sampleRate: 16000 });
            audioContextRef.current = audioCtx;

            const source = audioCtx.createMediaStreamSource(stream);
            await audioCtx.audioWorklet.addModule(
                // Inline worklet processor as data URL to avoid external file dependency
                URL.createObjectURL(new Blob([`
                    class PCMProcessor extends AudioWorkletProcessor {
                        process(inputs) {
                            const input = inputs[0]?.[0];
                            if (input) this.port.postMessage(input);
                            return true;
                        }
                    }
                    registerProcessor('pcm-processor', PCMProcessor);
                `], { type: 'application/javascript' }))
            );

            const processor = new AudioWorkletNode(audioCtx, 'pcm-processor');
            processorRef.current = processor;

            processor.port.onmessage = (e) => {
                if (ws.readyState !== WebSocket.OPEN) return;
                const pcm = e.data;
                // Convert float32 → int16 → base64
                const int16 = new Int16Array(pcm.length);
                for (let i = 0; i < pcm.length; i++) {
                    int16[i] = Math.max(-32768, Math.min(32767, Math.round(pcm[i] * 32767)));
                }
                const bytes = new Uint8Array(int16.buffer);
                let bin = '';
                for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
                const b64 = btoa(bin);
                ws.send(JSON.stringify({
                    realtime_input: {
                        media_chunks: [{ mime_type: 'audio/pcm;rate=16000', data: b64 }],
                    },
                }));
            };

            source.connect(processor);

            setIsListening(true);
            setStatusMsg('SIGINT ACTIVO — Análisis de audio en tiempo real');

        } catch (err) {
            setStatusMsg(`Error al iniciar: ${err.message}`);
            setIsListening(false);
        }
    }, [apiKey]);

    const stopListening = React.useCallback(() => {
        processorRef.current?.disconnect();
        audioContextRef.current?.close();
        mediaStreamRef.current?.getTracks().forEach(t => t.stop());
        wsRef.current?.close();
        setIsListening(false);
        setStatusMsg('Análisis detenido.');
    }, []);

    const toggleListening = () => {
        if (isListening) stopListening();
        else startListening();
    };

    // Cleanup on unmount
    React.useEffect(() => () => stopListening(), [stopListening]);

    // ---------------------------------------------------------------------------
    // "Enviar a C2" — save intel log to localStorage BMS
    // ---------------------------------------------------------------------------
    const sendToC2 = React.useCallback(() => {
        if (intelItems.length === 0) return;
        const existing = JSON.parse(localStorage.getItem(BMS_STORAGE_KEY) || '[]');
        const payload = {
            session_id: `SB-${Date.now()}`,
            captured_at: new Date().toISOString(),
            intel: intelItems,
        };
        existing.push(payload);
        localStorage.setItem(BMS_STORAGE_KEY, JSON.stringify(existing));
        setStatusMsg(`Intel enviada al BMS simulado — ${intelItems.length} entradas registradas.`);
    }, [intelItems]);

    const clearAll = () => {
        setTranscript([]);
        setIntelItems([]);
        setStatusMsg('Paneles limpiados.');
    };

    // ---------------------------------------------------------------------------
    // Render
    // ---------------------------------------------------------------------------
    return (
        <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%', p: 2, gap: 1.5 }}>
            {/* Header */}
            <Stack direction="row" alignItems="center" spacing={1.5}>
                <Typography variant="h5" sx={{ fontFamily: 'monospace', fontWeight: 700, letterSpacing: 2 }}>
                    ⚡ SANTA BÁRBARA — SIGINT TÁCTICO
                </Typography>
                <Chip
                    label={isListening ? 'EN ESCUCHA' : 'STANDBY'}
                    color={isListening ? 'error' : 'default'}
                    size="small"
                    sx={{ fontFamily: 'monospace', fontWeight: 700 }}
                />
            </Stack>

            {/* Status bar */}
            <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#9E9E9E' }}>
                {statusMsg}
            </Typography>

            {/* Controls */}
            <Stack direction="row" spacing={1} alignItems="center">
                <Tooltip title={isListening ? 'Detener análisis SIGINT' : 'Iniciar análisis SIGINT'}>
                    <IconButton
                        onClick={toggleListening}
                        color={isListening ? 'error' : 'primary'}
                        size="large"
                        sx={{ border: '2px solid', borderColor: isListening ? 'error.main' : 'primary.main' }}
                    >
                        {isListening ? <MicOffIcon /> : <MicIcon />}
                    </IconButton>
                </Tooltip>

                <Button
                    variant="contained"
                    color="warning"
                    startIcon={<SendIcon />}
                    onClick={sendToC2}
                    disabled={intelItems.length === 0}
                    sx={{ fontFamily: 'monospace', fontWeight: 700 }}
                >
                    Enviar a C2
                </Button>

                <Button
                    variant="outlined"
                    startIcon={<DeleteSweepIcon />}
                    onClick={clearAll}
                    sx={{ fontFamily: 'monospace' }}
                >
                    Limpiar
                </Button>

                <Box sx={{ flex: 1 }} />

                <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#616161' }}>
                    BMS: {JSON.parse(localStorage.getItem(BMS_STORAGE_KEY) || '[]').length} sesiones guardadas
                </Typography>
            </Stack>

            <Divider />

            {/* Split panel */}
            <Box sx={{ display: 'flex', flex: 1, gap: 2, overflow: 'hidden', minHeight: 0 }}>

                {/* Left: Literal transcription */}
                <Paper
                    variant="outlined"
                    sx={{
                        flex: 1,
                        display: 'flex',
                        flexDirection: 'column',
                        overflow: 'hidden',
                        bgcolor: '#0A0A0A',
                        borderColor: '#333',
                    }}
                >
                    <Box sx={{ px: 1.5, py: 0.75, borderBottom: '1px solid #222', bgcolor: '#111' }}>
                        <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#B0BEC5', letterSpacing: 1 }}>
                            TRANSCRIPCIÓN LITERAL
                        </Typography>
                    </Box>
                    <Box sx={{ flex: 1, overflow: 'auto', p: 1.5 }}>
                        {transcript.length === 0 ? (
                            <Typography variant="body2" sx={{ color: '#424242', fontFamily: 'monospace', fontStyle: 'italic' }}>
                                En espera de audio...
                            </Typography>
                        ) : (
                            transcript.map((entry) => (
                                <Typography key={entry.id} variant="body2" sx={{ fontFamily: 'monospace', color: '#B0BEC5', mb: 0.5, lineHeight: 1.5 }}>
                                    {entry.text}
                                </Typography>
                            ))
                        )}
                        <div ref={transcriptEndRef} />
                    </Box>
                </Paper>

                {/* Right: Tactical Intel */}
                <Paper
                    variant="outlined"
                    sx={{
                        flex: 1,
                        display: 'flex',
                        flexDirection: 'column',
                        overflow: 'hidden',
                        bgcolor: '#050505',
                        borderColor: '#1A2E1A',
                    }}
                >
                    <Box sx={{ px: 1.5, py: 0.75, borderBottom: '1px solid #1A2E1A', bgcolor: '#0A150A' }}>
                        <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#4CAF50', letterSpacing: 1 }}>
                            INTEL TÁCTICA SANTA BÁRBARA
                        </Typography>
                    </Box>
                    <Box sx={{ flex: 1, overflow: 'auto', p: 1.5 }}>
                        {intelItems.length === 0 ? (
                            <Typography variant="body2" sx={{ color: '#1B5E20', fontFamily: 'monospace', fontStyle: 'italic' }}>
                                Sin datos tácticos detectados...
                            </Typography>
                        ) : (
                            intelItems.map((item) => (
                                <Box
                                    key={item.id}
                                    sx={{
                                        mb: 1,
                                        p: 1,
                                        borderLeft: `3px solid ${typeColor(item.type)}`,
                                        bgcolor: item.type === 'EMERGENCY'
                                            ? 'rgba(255,61,61,0.08)'
                                            : item.type === 'MGRS_COORD'
                                                ? 'rgba(255,215,0,0.06)'
                                                : 'rgba(0,0,0,0.3)',
                                        borderRadius: '0 4px 4px 0',
                                    }}
                                >
                                    <Stack direction="row" spacing={1} alignItems="center" mb={0.3}>
                                        <Chip
                                            label={item.type}
                                            size="small"
                                            sx={{
                                                fontFamily: 'monospace',
                                                fontSize: '0.65rem',
                                                fontWeight: 700,
                                                height: 18,
                                                color: typeColor(item.type),
                                                borderColor: typeColor(item.type),
                                                bgcolor: 'transparent',
                                            }}
                                            variant="outlined"
                                        />
                                        <Typography variant="caption" sx={{ color: '#424242', fontFamily: 'monospace' }}>
                                            {new Date(item.ts).toLocaleTimeString()} · {Math.round(item.confidence * 100)}%
                                        </Typography>
                                    </Stack>
                                    <HighlightedText text={String(item.content)} type={item.type} />
                                </Box>
                            ))
                        )}
                        <div ref={intelEndRef} />
                    </Box>
                </Paper>
            </Box>
        </Box>
    );
}
