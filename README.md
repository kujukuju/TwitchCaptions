
# Twitch Captions

## Setup (English)

1. Modify config.txt to the correct settings.

2. In OBS create a browser source. Enable `local file`, and select `server/index.html`.

3. Run `captions.exe`.

> NOTE: The smaller models are faster but provide less accuracy.

## セットアップ (日本語)

1. config.txtを正しい設定に変更します。

2. OBSでブラウザソースを作成します。`ローカルファイル`を使用」を有効にし、`server/index.html`を選択します。

3. `captions.exe`を実行します。

> 注意: 小さいモデルは高速ですが、精度が低くなります。

## Config (English)

| Config Option                     | Purpose                                               | Valid Values                                      |
| ---                               | ---                                                   | ---                                               |
| original_language                 | The language being spoken.                            | (Any valid language code)                         |
| target_language                   | The language to translate to.                         | (Any valid language code)                         |
| model                             | The ML model to use for captioning.                   | ggml-base, ggml-medium, ggml-large-v3-q5_0        |
| lines                             | The amount of lines to display.                       | 0, 1, 2, 3, 4, etc...                             |
| display_original_language         | Whether or not to display the original spoken text.   | true, false                                       |
| use_local_english_translations    | Determines if the text should be locally translated using the ML model. Supposedly has better accuracy for spoken language. However, for this to work the target language has to be english and disply_original_language must be off. | true, false |
| include_notes                     | Whether or not the model should try to caption actions such as \*singing\* and \*keyboard typing\*. | true, false |
| step                              | Audio step size in milliseconds.                      | 1200, 2000, etc...                                |
| length                            | Audio length in milliseconds.                         | 5000, 10000, etc...                               |

## 設定 (日本語)

| 設定オプション                      | 目的                                                 | 有効な値                                            |
| ---                               | ---                                                   | ---                                               |
| original_language                 | 話されている言語。                                   | （有効な言語コード）                              |
| target_language                   | 翻訳先の言語。                                       | （有効な言語コード）                              |
| model                             | キャプションに使用するMLモデル。                      | ggml-base, ggml-medium, ggml-large-v3-q5_0        |
| lines                             | 表示する行数。                                       | 0, 1, 2, 3, 4, etc...                             |
| display_original_language         | 元の話されたテキストを表示するかどうか。             | true, false                                       |
| use_local_english_translations    | テキストをMLモデルでローカルに翻訳するかどうかを決定します。話し言葉の精度が高いとされています。ただし、これが機能するには、ターゲット言語が英語であり、display_original_languageがオフである必要があります。 | true, false |
| include_notes                     | モデルが \*歌う\* や \*キーボード入力\* などの動作をキャプション化するかどうか。 | true, false |
| step                              | オーディオのステップサイズ（ミリ秒単位）。           | 1200, 2000, など...                                |
| length                            | オーディオの長さ（ミリ秒単位）。                     | 5000, 10000, など...                               |

## Supported Languages

| Language Code | Language Name     |
| ---           | ---               |
| en            | English           |
| zh            | Chinese           |
| de            | German            |
| es            | Spanish           |
| ru            | Russian           |
| ko            | Korean            |
| fr            | French            |
| ja            | Japanese          |
| pt            | Portuguese        |
| tr            | Turkish           |
| pl            | Polish            |
| ca            | Catalan           |
| nl            | Dutch             |
| ar            | Arabic            |
| sv            | Swedish           |
| it            | Italian           |
| id            | Indonesian        |
| hi            | Hindi             |
| fi            | Finnish           |
| vi            | Vietnamese        |
| he            | Hebrew            |
| uk            | Ukrainian         |
| el            | Greek             |
| ms            | Malay             |
| cs            | Czech             |
| ro            | Romanian          |
| da            | Danish            |
| hu            | Hungarian         |
| ta            | Tamil             |
| no            | Norwegian         |
| th            | Thai              |
| ur            | Urdu              |
| hr            | Croatian          |
| bg            | Bulgarian         |
| lt            | Lithuanian        |
| la            | Latin             |
| mi            | Maori             |
| ml            | Malayalam         |
| cy            | Welsh             |
| sk            | Slovak            |
| te            | Telugu            |
| fa            | Persian           |
| lv            | Latvian           |
| bn            | Bengali           |
| sr            | Serbian           |
| az            | Azerbaijani       |
| sl            | Slovenian         |
| kn            | Kannada           |
| et            | Estonian          |
| mk            | Macedonian        |
| br            | Breton            |
| eu            | Basque            |
| is            | Icelandic         |
| hy            | Armenian          |
| ne            | Nepali            |
| mn            | Mongolian         |
| bs            | Bosnian           |
| kk            | Kazakh            |
| sq            | Albanian          |
| sw            | Swahili           |
| gl            | Galician          |
| mr            | Marathi           |
| pa            | Punjabi           |
| si            | Sinhala           |
| km            | Khmer             |
| sn            | Shona             |
| yo            | Yoruba            |
| so            | Somali            |
| af            | Afrikaans         |
| oc            | Occitan           |
| ka            | Georgian          |
| be            | Belarusian        |
| tg            | Tajik             |
| sd            | Sindhi            |
| gu            | Gujarati          |
| am            | Amharic           |
| yi            | Yiddish           |
| lo            | Lao               |
| uz            | Uzbek             |
| fo            | Faroese           |
| ht            | "haitiancreole    |
| ps            | Pashto            |
| tk            | Turkmen           |
| nn            | Nynorsk           |
| mt            | Maltese           |
| sa            | Sanskrit          |
| lb            | Luxembourgish     |
| my            | Myanmar           |
| bo            | Tibetan           |
| tl            | Tagalog           |
| mg            | Malagasy          |
| as            | Assamese          |
| tt            | Tatar             |
| haw           | Hawaiian          |
| ln            | Lingala           |
| ha            | Hausa             |
| ba            | Bashkir           |
| jw            | Javanese          |
| su            | Sundanese         |
| yue           | Cantonese         |
