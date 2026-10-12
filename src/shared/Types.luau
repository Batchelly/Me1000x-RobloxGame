--[[
	Types.luau
	Tipos compartilhados entre servidor e cliente.
]]

export type UpgradeLevels = {
	Record: number,
	Speed: number,
}

-- Fita salva no DataStore.
--   P = caminho comprimido (buffer -> Base64). Fitas da Pista ficam no espaço LOCAL do plot.
--   F = caída, Z = "city" | "track", K = cor da fita (BrickColor), N = nome na etiqueta,
--   O = nome de quem gravou (fitas roubadas guardam o autor original).
export type SavedClone = {
	P: string,
	F: boolean?,
	Z: string?,
	K: string?,
	N: string?,
	O: string?,
}

export type Settings = {
	Music: number,
	Ambient: number,
	Sfx: number,
	CloneQuality: number,
	Alerts: boolean,
}

-- Perfil salvo do jogador (tudo que vai para o DataStore).
export type PlayerData = {
	Version: number,
	Cash: number,
	Rebirths: number,
	TotalEarned: number,
	Upgrades: UpgradeLevels,
	BaseLevel: number,
	VaultCash: number,
	Clones: { [string]: SavedClone }, -- chave = slot ("1", "2", ...)
	LastStolen: SavedClone?, -- última fita roubada (produto RecoverTape)
	Bananas: number,
	LastBananaRefill: number, -- os.time()
	ShieldUntil: number, -- os.time()
	Cosmetics: { [string]: boolean },
	PurchaseHistory: { string }, -- PurchaseIds já processados (idempotência)
	LastLogin: number, -- os.time() do último save/saída (base da renda offline)
	EarnPerMin: number, -- média de ganho/min dos clones na última sessão
	PendingOfflineDouble: number, -- valor que o produto DoubleOffline pode dobrar
	Daily: { Streak: number, LastDay: number },
	GroupRewardClaimed: boolean,
	RedeemedCodes: { [string]: boolean },
	Settings: Settings,
	PlayTime: number,
}

-- Informação de um clone enviada aos clientes.
export type CloneInfo = {
	id: number,
	ownerId: number,
	ownerName: string,
	slot: number,
	golden: boolean,
	fallen: boolean,
	fallenPhase: number,
	transit: boolean,
	startTime: number,
	path: buffer,
	color: Color3,
	zone: string,
	label: string,
	debug: boolean?,
}

export type CloneSummary = {
	slot: number,
	fallen: boolean,
	golden: boolean,
	transit: boolean,
	zone: string,
	label: string,
	tapeColor: string,
	origin: string?,
	rate: number,
	cloneId: number,
}

-- Estado do jogador enviado ao cliente (StateSync).
export type ClientState = {
	loaded: boolean,
	cash: number,
	rebirths: number,
	multiplier: number,
	nextMultiplier: number,
	rebirthCost: number,
	slots: number,
	cloneCount: number,
	fallenCount: number,
	clones: { CloneSummary },
	bananas: number,
	bananaRefillLeft: number,
	shieldLeft: number,
	coinRainLeft: number,
	recordSeconds: number,
	walkSpeed: number,
	upgrades: UpgradeLevels,
	prices: { [string]: number? },
	passes: { [string]: boolean },
	cashPacks: { [string]: number },
	daily: { available: boolean, day: number },
	groupClaimed: boolean,
	offline: { amount: number, minutes: number }?,
	recording: boolean,
	vip: boolean,
	-- v2: base
	plot: number?,
	baseLevel: number,
	nextLevelPrice: number?,
	vaultCash: number,
	vaultCapacity: number,
	lockedUntil: number, -- relógio do servidor (Clock.now())
	cooldownUntil: number,
	protectedUntil: number,
	carrying: boolean,
	hasStolenTape: boolean,
	settings: Settings,
}

export type PickupFx = {
	pos: Vector3,
	amount: number,
	color: Color3,
	kind: string,
}

return {}
