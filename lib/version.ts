import releaseVersion from "@/version.json";

const { major, update, fix } = releaseVersion;

export const APP_VERSION_LABEL = `v${major}.${String(update).padStart(2, "0")}.${fix}`;
