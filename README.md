# 使用 Prometheus 和 Grafana 打造監控預警系統 (Docker 篇)

還記得我們上次架設 EFK 來獲得容器的日誌嗎！？身為一個 SRE 除了收集日誌外，還需要監控每個系統或是服務的運行狀況，並在警急情況即時通知相關人員作為應對處理。所以透過好的 Monitoring/Alert System 了解目前 Server 硬體系統狀況和整個 Service 的網路狀況是一件非常重要的一件事情。

在眾多的 Monitor 工具中，[Prometheus](https://prometheus.io/) 是一個很方便且完善的監控預警框架 TSDB (Time Series Database) 時間序列資料庫，可以快速且容易的建立不同維度的指標 (Metrics) 和整合不同的 Alert Tool 以及資訊視覺化圖表的監控工具並提供自帶的 [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/) 進行 query 查詢。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/prometheus.png)

<br>

我們先來看看 Prometheus 的架構圖，可以更了解 Prometheus 整體的定位：

<br>


![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/prometheus-architecture.jpg)
(圖片來源：[使用 Prometheus 和 Grafana 打造 Flask Web App 監控預警系統](https://blog.techbridge.cc/2019/08/26/how-to-use-prometheus-grafana-in-flask-app/))


<br>
 
1. 有一個 Prometheus server 主體，會去 Prometheus Client Pull 相關的指標 (Metrics)，若是短期的 Job 例如 CronJob 在還來不及 Pull 資料回來可能就已經完成任務了、清洗掉資料。所以會有一個 `pushgateway` 接收 Job Push 過來的相關資訊，Prometheus Server 再從其中拉取資料。 (圖片左半部)

2. Service Discovery 可以更好的蒐集 Kubernetes 相關的資訊。 (圖片上半部)

3. Prometheus Server 主體會將資料儲存在 Local On-Disk  Time Series Database 或是可以串接 Remote Storage Systems。(圖片下半部)

4. Prometheus Server 資料拉回來後可以使用本身自帶的 Web UI 或是 Grafana 等其他的 Client 來呈現。(圖片右下半部)

5. 當抓取資料的值超過 Alert Rule 所設定的閥值 (threshold) 時，Alertmanager 就會將訊息送出，可以透過 Email、Slack 等訊息通知，提醒相關人員進行處理。(圖片右上半部)

<br>

Prometheus 可能在儲存擴展上比不上其他 Time Series Database，但在整合各種第三方的 Data Source 上十分方便，且在支援雲端服務和 Container 容器相關工具也十分友好。但在圖片的表現上就相較於單薄，所以會搭配我們接下來要介紹的 Grafanac 精美儀表板工具來進行資訊視覺化和圖表的呈現。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/grafana.jpg)

<br>

Grafana 是由 Grafana Lab 經營的一個非常精美的儀表板系統，可以整合各種不同的 Data Source，例如：Prometheus、Elasticsearch、MySQL、PostgreSQL等。透過不同種指標 (Metrics) 呈現在 Dashboard 上。如果還是不太清楚，可以把 Prometheus Grafana 分別想成 Prometheus 是 EFK 的 Elasticsearch，Grafana 想成是 EFK 的 Kibana。

<br>

今天我們要透過 Docker-Compose 搭配 Nginx 實作一個簡單的 Web Service 範例，並整合 [Prometheus](https://prometheus.io/) 和 [Grafana](https://grafana.com/) 來建立一個 Web Service 監控預警系統。

此文章程式碼也會同步到 Github ，需要的也可以去查看歐！要記得先確定一下自己的版本 [Github 程式碼連結](https://github.com/880831ian/Prometheus-Grafana-Docker) 😆

<br>

## 版本資訊

* macOS：11.6
* Docker：Docker version 20.10.14, build a224086
* Nginx：[1.21.6](https://hub.docker.com/layers/nginx/library/nginx/1.21.6/images/sha256-b495f952df67472c3598b260f4b2e2ba9b5a8b0af837575cf4369c95c8d8a215?context=explore)
* Prometheus：[v.2.35.0](https://hub.docker.com/layers/prometheus/prom/prometheus/v2.35.0/images/sha256-4b86ad59abc67fa19a6e1618e936f3fd0f6ae13f49260da55a03eeca763a0fb5?context=explore)
* nginx-prometheus-exporter：[0.10](https://hub.docker.com/layers/nginx-prometheus-exporter/nginx/nginx-prometheus-exporter/0.10/images/sha256-f2aa9848516ff4c9f4c6d5bcb758b0fab519eff644f526e4c9a17d3083b54dde?context=explore)
* Grafana：[8.2.5](https://hub.docker.com/layers/grafana/grafana/grafana/8.2.5/images/sha256-1a154d1161ed65eaf87368d08149a8bbcf9962ac03dd5ff639a6b9d468a77a36?context=explore) (最新版本是 8.5.2，但選擇 8.2.5，是因為 8.3.0 後 Alerting 沒有辦法附上圖片，詳細原因可以參考 [Add "include image" option into Grafana Alerting](https://github.com/grafana/grafana/discussions/38030) )
* grafana/grafana-image-renderer：[3.4.2](https://hub.docker.com/layers/grafana-image-renderer/grafana/grafana-image-renderer/3.4.2/images/sha256-fd9d7b764597e84e447e6c8440e44e18c9f74728e3928156ea92599fe6f19e7d?context=explore)

<br>

## 檔案結構

```sh
.
├── docker-compose.yaml
├── nginx
│   ├── Dockerfile
│   └── status.conf
├── prometheus.yaml
└── test.sh
```

這是主要的結構，簡單說明一下：

* docker-compose.yaml：會放置要產生的 nginx、nginx-prometheus-exporter、prometheus、grafana、grafana-image-renderer 容器設定檔。
* nginx/Dockerfile：因為在 nginx 要使用 stub_status 需要多安裝一些設定，所以用 Dockerfile 另外寫 nginx 的映像檔。
* nginx/status.conf：nginx 的設定檔。
* prometheus.yaml：prometheus 的設定檔。
* test.sh：測試用檔案(後續會教大家如何使用)。

<br>

## 實作

接下來會依照執行的流程來跟大家說明歐！那要開始囉 😁

我們要建立一個 Nginx 來模擬受監控的服務，我們要透過 nginx-prometheus-exporter 來讓 Prometheus 抓到資料最後傳給 Grafana，所以我們在 Docker-compose 裡面會有 nginx、nginx-prometheus-exporter、prometheus、grafana、grafana-image-renderer 幾個容器，我們先看一下程式碼，再來說明程式碼設定了哪些東西吧！

### Docker-compose.yaml

```yaml
version: '3.8'
services:
  nginx:
    build: ./nginx/
    container_name: nginx
    ports:
      - 8080:8080

  nginx-prometheus-exporter:
    image: nginx/nginx-prometheus-exporter:0.10
    container_name: nginx-prometheus-exporter
    command: -nginx.scrape-uri http://nginx:8080/stub_status
    ports:
      - 9113:9113
    depends_on:
      - nginx

  prometheus:
    image: prom/prometheus:v2.35.0
    container_name: prometheus
    volumes:
      - ./prometheus.yaml:/etc/prometheus/prometheus.yaml
      - ./prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yaml'
    ports:
      - '9090:9090'

  renderer:
    image: grafana/grafana-image-renderer:3.4.2
    environment:
      BROWSER_TZ: Asia/Taipei
    ports:
      - '8081:8081'

  grafana:
    image: grafana/grafana:8.2.5
    container_name: grafana
    volumes:
      - ./grafana_data:/var/lib/grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: pass
      GF_RENDERING_SERVER_URL: http://renderer:8081/render
      GF_RENDERING_CALLBACK_URL: http://grafana:3000/
      GF_LOG_FILTERS: rendering:debug
    depends_on:
      - prometheus
      - renderer
    ports:
      - '3000:3000'
```
* nginx：因為 Nginx 會通過 stub_status 頁面來開放對外的監控指標。所以我們要另外寫一個 Dockerfile 設定檔，先將 `conf` 放入 Nginx 中。
* nginx-prometheus-exporter：這裡要注意的是需要使用 command 來設定 nginx.scrapt-url，我們設定 `http://nginx:8080/stub_status`，他的預設 Port 是 `9113`，並設定依賴 `depends_no`，要 nginx 先啟動後才會執行 `nginx-prometheus-exporter`。
* prometheus：將 prometheus.yaml 設定檔放入 `/etc/prometheus/prometheus.yaml`，以及掛載一個 `/prometheus_data` 來永久保存 prometheus 的資料，最後 command 加入 `--config.file` 設定。
*  renderer：這是 grafana 顯示圖片的套件，我們使用 3.4.2 版本，記得要設定環境變數，照片顯示的時間才會正確，並開啟 8081 Port 讓 grafana 訪問。
* grafana：一樣我們先掛載一個 `/grafana_data` 來永久保存 grafana 的設定，在環境變數中設定預設帳號 `admin` 的密碼是 `pass`，設定 renderer 套件的服務位置是 `http://renderer:8081/render` 以及回傳到 `http://grafana:3000/`，並設定依賴 `depends_on` prometheus 跟 renderer，最後設定 grafana 要呈現的畫面 3000 Port。

<br>

### nginx/Dockerfile

```dockerfile
FROM nginx:1.21.6  
COPY ./status.conf /etc/nginx/conf.d/status.conf 
```
選擇我們要使用的 nginx image 版本，並將我們的設定檔，複製到容器內。

<br>

### nginx/status.conf

```conf
server {
    listen 8080;
    server_name  localhost;
    location /stub_status {
       stub_status on;
       access_log off;
    }
}
```
這邊最重要的就是要設定 `/stub_status` 路徑，並開啟 stub_status ，這樣才可以讓 nginx-prometheus-exporter 抓到資料！(要怎麼知道 Nginx 是否開啟 `stub_status`，可以使用 `nginx -V 2>&1 | grep -o with-http_stub_status_module` 指令檢查，我們這次裝的 Image 已經有幫我們啟動)

<br>

### prometheus.yaml

```yaml
global:
  scrape_interval: 5s # Server 抓取頻率
  external_labels:
    monitor: "my-monitor"
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "nginx_exporter"
    static_configs:
      - targets: ["nginx-prometheus-exporter:9113"]
```
這邊是 prometheus 的設定檔，例如有 scrape_interval 代表 Server 每次抓取資料的頻率，或是設定 monitor 的 labels，下面的 configs，分別設定了 prometheus 它的 targets 是 `["localhost:9090"]` 以及 nginx_exporter 它的 targets 是 `["nginx-prometheus-exporter:9113"]`。

<br>

### test.sh

```sh
#!/bin/bash

docker="docker exec nginx"

for i in {1..10}
do
	$docker curl http://nginx:8080/stub_status -s
done
```
這個是我自己另外寫的測試程式，在本機執行後他會訪問 nginx 容器內部，並模擬 nginx 流量，讓我們在 Grafana 可以清楚看到資料。

<br>

### 執行/測試

當我們都寫好設定檔後，在專案目錄下，也就是有 Docker-compose 路徑下，使用 `docker-compose up -d` 來啟動容器：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_1.png)

<br>

接下來我們依序檢查容器是否都有正常運作，開啟瀏覽器瀏覽 `http://localhost:9113/metrics` 查看是否有出現跟下面圖片差不多的內容：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_2.png)

如果有出現，恭喜你完成了 Nginx 以及 nginx-prometheus-exporter 的設定，我們將  Nginx 的 `stub_status` 服務，透過 `http://nginx:8080/stub_status` 讓 nginx-prometheus-exporter 可以抓到圖片中的這些指標 (Metrics)。

<br>

#### Prometheus 

接著我們瀏覽 `http://localhost:9090/targets`，看看我們的 Prometheus 有沒有設定正確，抓到我們設定好的 targets：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_3.png)

如果兩個出現的都是 <font color='green'>綠色的 UP</font> 就代表正常有抓到資料囉！

<br>

那要怎麼測試才知道有抓到資料呢？我們可以先用 Prometheus 內建的圖形化介面來檢查，在瀏覽器瀏覽 `http://localhost:9090/graph` 就可以看到下面的畫面：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_4.png)

<br>

我們選擇 `Graph`，並在上面的搜尋欄，打上 `nginx_connections_accepted` 按下右邊的 Execute 就會產生一張圖表，圖表裡面只有一條綠色的線，那這個線是什麼呢？它就是我們剛剛在  `http://localhost:9113/metrics` 其中一個指標 (Metrics)，它代表 Nginx 接受用戶端連接總數量：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_5.png)

這個功能就是把我們所收到的 Nginx 指標 (Metrics)，轉換成圖表讓我們可以知道他的變化。

<br>

為了更明顯的看出變化，這時候就要使用我所寫好的 `test.sh` 腳本，使用 `sh test.sh` 來執行，再回來觀察圖型是否變化：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_6.png)

可以發現剛剛原本只有 1 個的連接數因為我們模擬總共跑了 10 次，所以連接數變成 11 了！

<br>

#### Grafana 

Prometheus 的圖形化比較單調，所以我們使用 Grafana 來美化我們的儀表板，瀏覽器瀏覽 `http://localhost:3000/` ，可以看到一個登入頁面：帳號是 `admin`，密碼是我們在環境變數中所設定的 `pass`：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_7.png)

<br>

登入後我們看到首頁，選擇 **Add your first data source** 來新增資料來源：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_8.png)

<br>

選擇第一個 **Prometheus**，我們到 HTTP 的 URL 設定 `http://prometheus:9090` 其他設定在我們測試環境中，不需要去調整，滑到最下面按下 **Save & test**：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_9.png)

<br>

接著我們要來設計我們的儀表板，在 Grafana 除了自己設計以外，還可以 Import 別人做好的儀表板。

我們點選左側欄位的 **＋** 符號 > 裡面的 **Import**，可以在這邊 Import 別人做好的儀表板，使用方式也很簡單，只需要先去 [Grafana Labs dashboard](https://grafana.com/grafana/dashboards/) 裡面找到自己要使用的儀表板，右側會有一個 ID，把 ID 貼上我們的 Grafana 就 Import 成功囉！很神奇吧XD 

我們要使用的儀表板是別人已經做好的 [NGINX exporter](https://grafana.com/grafana/dashboards/12708)，它的 ID 是 `12708`，把 ID 貼入後，按下 **Load**，就會有 NGINX exporter 的基本資訊，我們在最下面的 Prometheus 選擇我們要使用的 data source，就是我們剛剛先設定好的 
**Prometheus**，最後按下 **Import**，就完成拉。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_10.png)

<br>

如果設定都沒有錯誤的話，應該可以看到下面這個畫面，最上面是監測 Nginx 服務的狀態，以及下方有不同的指標在顯示：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_11.png)

<br>

接下來我們一次用 `test.sh` 來測試一下是否有成功抓到資料：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_12.png)
可以看到在我們使用完測試腳本後，在該時段的資料有明顯的不一樣，代表我們有成功抓到資料 😄

<br>

此外也可以將 Nginx 服務暫停，看看儀表板上方的 NGINX Status 狀態是否改變：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/run_13.png)

<br>

#### Alerting 警報

當然除了監控以外，我們還需要有警報系統，因為我們不可能每天都一直盯著儀表板看哪裡有錯誤，所以我們要設定警報的規則，以及警報要發送到哪裡，接著我們一起看下去吧：

我們先點左側的 **Alerting 🔔** &nbsp; > 點選 **Notification channels** 來新增我們要發送到哪裡。這次我們一樣使用 Telegram，我們在 type 下拉式選單選擇 **Telegram**，輸入我們的 BOT API Token 以及 Chat ID，儲存之前可以點選 **test** 來測試！

<br>

怎麼使用 Telegram Bot?

請參考這一篇 [Ansible 介紹與實作 (Inventory、Playbooks、Module、Template、Handlers)](https://pin-yi.me/ansible/#ansible-發送通知到-telegram-bot) 來取得 BOT API Token 以及 Chat ID。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_1.png)

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_2.png)

<br>

接著我們來設計一個屬於我們的控制板 (Panel)，順便幫他加上 Alerting，稍後也用 `test.sh`，看看他會不會自動發出提醒到 Telegram Bot 😬

首先點選左側欄位的 **＋** 符號 > 裡面的 Create，在選擇 **Add an empty panel**：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_3.png)

<br>

再 Query 的 **A** Metrics browser 輸入 `nginx_connections_accepted` 一樣來取得 Nginx 接受用戶端連接總數量的圖表，到右上角選擇 **Last 5 minutes**，旁邊的圖型我們選擇 *Graph (old)*，下面的 Title 可以修改一下這個圖表的名稱，最後按下 **Save**，就可以看到我們建好一個控制板囉 🥳	

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_4.png)

<br>

接著我們來設定 Alert，可以看到剛剛在 **Query** 旁邊有一個 Alert，點進去後按 **Create Alert**，我們先修改 Evaluate every 後面的 For 改為 `1m` (代表當數值超過我們所設定的閥值後，狀態會從 OK 變成 Pending，這時候還不會發送警報，會等待我們現在設定的 `1m` 分鐘後，情況還是沒有好轉，才會發送通知)，再 Conditions 後面欄位加入 10 (我們所設定的閥值，代表 `nginx_connections_accepted` 超過 10 就會進入 Pending 狀態)，往下滑 Notifications 的 **Send to** 選擇我們上面所建立的 channels 名稱，按下 **Save**。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_5.png)

<br>

接著執行 `test.sh` 兩次，讓 `nginx_connections_accepted` 超過我們所設定的閥值，可以看到控制板超過 10 以上變成紅色：

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_6.png)

<br>

接著等待幾分鐘後，狀態會從 OK 綠色變成黃色的 Pending，最後轉成紅色的 Alert，這時候 Telegram 就會收到通知囉 ❌

<br>

![圖片](https://raw.githubusercontent.com/880831ian/Prometheus-Grafana-Docker/master/images/alert_7.png)

<br>

## Nginx 指標 (Metrics) 描述

我們在 `http://localhost:9113/metrics` 中可以看到許多指標 (Metrics) 那他們各代表什麼意思呢？我把它整理成表格讓大家可以選擇要使用的指標 (Metrics)：

| 指標 | 描述 |
| :---: | :---: |
| nginx_connections_accepted	 | 接受用戶端的連接總數量 |
| nginx_connections_active | 當前用戶端連接數量 |
| nginx_connections_handled | Handled 狀態的連接數量 |
| nginx_connections_reading | 正在讀取的用戶端連接數量 |
| nginx_connections_waiting | 正在等待中的用戶端連接數量 |
| nginx_connections_writing | 正在寫入的用戶端連接數量 |
| nginx_http_requests_total | 客戶端總請求數量 |
| nginx_up | Nginx Exporter 是否正常運行 |
| nginxexporter_build_info | Nginx Exporter 的構建資訊 |

<br>

## 參考資料

[使用 Prometheus 和 Grafana 打造 Flask Web App 監控預警系統](https://blog.techbridge.cc/2019/08/26/how-to-use-prometheus-grafana-in-flask-app/)

[Nginx Exporter 接入](https://cloud.tencent.com/document/product/1416/56039)

[通過nginx-prometheus-exporter監控nginx指標](https://maxidea.gitbook.io/k8s-testing/prometheus-he-grafana-de-dan-ji-bian-pai/tong-guo-nginxprometheusexporter-jian-kong-nginx)

[使用nginx-prometheus-exporter 監控nginx](https://www.cnblogs.com/rongfengliang/p/13580534.html)

[使用阿里雲Prometheus監控Nginx（新版）](https://help.aliyun.com/document_detail/171819.html?spm=5176.22414175.sslink.29.6c9e1df9DdpLPP)

[Grafana Image Renderer](https://grafana.com/grafana/plugins/grafana-image-renderer/)

[grafana的image render设置](https://blog.csdn.net/dandanfengyun/article/details/115346594)