/// Niet-web-variant van [mem_asset_blob.dart]. Buiten de browser bestaat er
/// geen blob-URL, en een `mem:`-pad komt op deze platformen nooit langs
/// (pakketten pakken naar schijf uit), dus er valt niets op te lossen.
String? memAssetBlobUrl(String memPath) => null;
