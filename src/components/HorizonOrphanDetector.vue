<template>
<div class="horizon-orphan-container">
  <el-card class="box-card">
    <div slot="header" class="clearfix">
      <span class="analysis-title">
        <i class="fa fa-stethoscope"></i> Horizon Orphan Detector
      </span>
      <i v-if="isScanning" class="el-icon-loading"></i>
      <el-tag size="mini">Orphans: {{orphanList.length}}</el-tag>
      <el-tag size="mini" type="warning">Scanned: {{scannedCount}}</el-tag>
      <el-button v-if="scanningEnd" @click="startScan" class="operate-btn" type="primary" size="mini">
        <i class="fa fa-refresh"></i> {{ $t('message.restart') }}
      </el-button>
      <el-button v-else-if="isScanning" @click="toggleScanning(true)" class="operate-btn" type="danger" size="mini">
        <i class="fa fa-pause"></i> {{ $t('message.pause') }}
      </el-button>
      <el-button v-else @click="toggleScanning(false)" class="operate-btn" size="mini">
        <i class="fa fa-play"></i> {{ $t('message.begin') }}
      </el-button>
      <el-button v-if="orphanList.length > 0" @click="confirmDeleteOrphans" class="operate-btn" type="danger" size="mini" style="margin-right: 8px;">
        <i class="fa fa-trash"></i> Delete Orphans
      </el-button>
    </div>

    <div class="config-section">
      <div class="config-row">
        <span class="config-label">Preset:</span>
        <el-select v-model="preset" @change="applyPreset" size="mini" style="width: 200px;">
          <el-option label="horizon:job:*" value="horizon"></el-option>
          <el-option label="{horizon}:job:*" value="brace"></el-option>
          <el-option label="Custom" value="custom"></el-option>
        </el-select>
        <span class="config-label" style="margin-left: 16px;">Hash Pattern:</span>
        <el-input v-model="hashPattern" size="mini" placeholder="horizon:job:*" style="width: 200px;"></el-input>
      </div>
      <div class="config-row" style="margin-top: 8px;">
        <span class="config-label">ID Prefix:</span>
        <el-input v-model="idPrefix" size="mini" placeholder="horizon:job:" style="width: 200px;"></el-input>
        <span class="config-label" style="margin-left: 16px;">Reference ZSets:</span>
        <el-input v-model="zsetKeysInput" size="mini" placeholder="horizon:recent_jobs,horizon:failed_jobs" style="width: 320px;"></el-input>
        <el-tooltip content="Comma-separated list of ZSet keys">
          <i class="el-icon-question" style="margin-left: 6px; color: #909399;"></i>
        </el-tooltip>
      </div>
    </div>

    <div class="keys-header">
      <span class="header-title">Key</span>
      <span class="header-title size-header">Size</span>
      <span class="header-title type-header">Type</span>
    </div>

    <RecycleScroller class="keys-body" :items="orphanList" :item-size="24" key-field="str" v-slot="{ item, index }">
      <li @click="clickJump(item)">
        <span class="list-index">{{ index + 1 }}.</span>
        <span class="key-name" :title="item.str">{{ item.str }}</span>
        <span class="key-type"><el-tag size="mini" type="info">{{ item.type }}</el-tag></span>
        <span class="size"><el-tag size="mini" :type="item.tagType || ''">{{ item.human }}</el-tag></span>
      </li>
    </RecycleScroller>

    <div v-if="orphanList.length === 0 && scanningEnd" class="empty-result">
      <i class="fa fa-check-circle" style="color: #67c23a;"></i> No orphan keys found.
    </div>
  </el-card>
</div>
</template>

<script>
import { RecycleScroller } from 'vue-virtual-scroller';

export default {
  data() {
    return {
      isScanning: false,
      scanningEnd: false,
      scanStreams: [],
      orphanList: [],
      scannedCount: 0,
      preset: 'horizon',
      hashPattern: 'horizon:job:*',
      idPrefix: 'horizon:job:',
      zsetKeysInput: 'horizon:recent_jobs,horizon:failed_jobs,horizon:completed_jobs,horizon:silenced_jobs',
      scanPageSize: 2000,
      scanMax: 200000,
    };
  },
  props: ['client', 'hotKeyScope'],
  components: { RecycleScroller },
  computed: {
    zsetKeys() {
      return this.zsetKeysInput.split(',').map(s => s.trim()).filter(Boolean);
    },
  },
  methods: {
    startScan() {
      this.orphanList = [];
      this.scannedCount = 0;
      this.isScanning = true;
      this.scanningEnd = false;
      this.scanStreams = [];
      this.initScanStreamsAndScan();
    },
    applyPreset(val) {
      const presets = {
        horizon: {
          hashPattern: 'horizon:job:*',
          idPrefix: 'horizon:job:',
          zsetKeysInput: 'horizon:recent_jobs,horizon:failed_jobs,horizon:completed_jobs,horizon:silenced_jobs',
        },
        brace: {
          hashPattern: '{horizon}:job:*',
          idPrefix: '{horizon}:job:',
          zsetKeysInput: '{horizon}:recent_jobs,{horizon}:failed_jobs,{horizon}:completed_jobs,{horizon}:silenced_jobs',
        },
      };
      const cfg = presets[val];
      if (cfg) {
        this.hashPattern = cfg.hashPattern;
        this.idPrefix = cfg.idPrefix;
        this.zsetKeysInput = cfg.zsetKeysInput;
      }
    },
    initScanStreamsAndScan() {
      const nodes = this.client.nodes ? this.client.nodes('master') : [this.client];
      this.scanningCount = nodes.length;
      nodes.forEach((node) => {
        const stream = node.scanBufferStream({ match: this.hashPattern, count: this.scanPageSize });
        this.scanStreams.push(stream);
        stream.on('data', (keys) => {
          stream.pause();
          if (this.scannedCount > this.scanMax) {
            this.$message.warning(this.$t('message.max_scan', { num: this.scanMax }) + ', stopped.');
            this.scanningEnd = true;
            return this.toggleScanning(true);
          }
          this.processKeys(keys).then(() => {
            this.scannedCount += keys.length;
            setTimeout(() => { this.isScanning && stream.resume(); }, 50);
          });
        });
        stream.on('error', (e) => { this.toggleScanning(true); this.$message.error('Scan Error: ' + e.message); });
        stream.on('end', () => { if (--this.scanningCount <= 0) { this.isScanning = false; this.scanningEnd = true; } });
      });
    },
    async processKeys(keys) {
      if (!keys || !keys.length) return;
      const allPromise = [];
      for (const key of keys) {
        const keyStr = this.$util.bufToString(key);
        const promise = this.checkOrphan(key, keyStr).then((result) => {
          if (result && result.isOrphan) {
            this.orphanList.push({ key, str: keyStr, size: result.size, human: result.human, type: result.type, tagType: result.tagType, errMsg: result.errMsg });
            this.orphanList.sort((a, b) => b.size - a.size);
          }
        });
        allPromise.push(promise);
      }
      return Promise.all(allPromise);
    },
    async checkOrphan(key, keyStr) {
      const type = await this.client.call('TYPE', key).catch(() => 'none');
      if (type !== 'hash') return null;
      const jobId = keyStr.startsWith(this.idPrefix) ? keyStr.slice(this.idPrefix.length) : keyStr;
      let found = false;
      for (const zsetKey of this.zsetKeys) {
        const score = await this.client.call('ZSCORE', zsetKey, jobId).catch(() => null);
        if (score !== null && score !== undefined) { found = true; break; }
      }
      if (found) return null;
      let size = 0, human = 'N/A', tagType = '', errMsg = '';
      try {
        const reply = await this.client.call('MEMORY', 'USAGE', key);
        size = parseInt(reply, 10) || 0;
        human = this.$util.humanFileSize(size);
      } catch (e) {
        try {
          const dumpReply = await this.client.call('DUMP', key);
          if (dumpReply) { size = dumpReply.length; human = '~' + this.$util.humanFileSize(size); tagType = 'info'; }
        } catch (dumpErr) { human = 'Err'; tagType = 'danger'; errMsg = (e && e.message) || 'Size error'; }
      }
      return { isOrphan: true, size, human, type: 'hash', tagType, errMsg };
    },
    clickJump(item) { this.$bus.$emit('clickedKey', this.client, item.key, true); },
    toggleScanning(pause = true) {
      if (pause) {
        this.isScanning = false;
        this.scanStreams.forEach(s => s.pause && s.pause());
        return;
      }
      if (this.scanningEnd) return;
      this.isScanning = true;
      this.scanStreams.forEach(s => s.pause && s.resume());
    },
    confirmDeleteOrphans() {
      this.$confirm('Delete ' + this.orphanList.length + ' orphan keys? This cannot be undone.', 'Confirm Delete', { type: 'warning', confirmButtonText: 'Delete', confirmButtonClass: 'el-button--danger' }).then(() => this.deleteOrphans()).catch(() => {});
    },
    async deleteOrphans() {
      const keys = this.orphanList.map(item => item.key);
      const total = keys.length;
      if (total <= 0) return;
      this.$message.info('Deleting ' + total + ' orphan keys...');
      try {
        if (!this.client.nodes) {
          let deleted = 0;
          for (let i = 0; i < total; i += 5000) {
            const batch = keys.slice(i, i + 5000);
            const reply = await this.client.del(batch);
            deleted += reply || 0;
          }
          this.$message.success('Deleted ' + deleted + ' orphan keys.');
        } else {
          let deleted = 0;
          for (const key of keys) { const reply = await this.client.del(key); deleted += reply || 0; }
          this.$message.success('Deleted ' + deleted + ' orphan keys.');
        }
        this.orphanList = [];
        this.$bus.$emit('refreshKeyList', this.client);
      } catch (e) { this.$message.error('Delete failed: ' + e.message); }
    },
  },
  mounted() { this.startScan(); },
  beforeDestroy() { this.toggleScanning(true); },
};
</script>

<style>
.horizon-orphan-container .analysis-title { font-weight: bold; font-size: 120%; }
.horizon-orphan-container .operate-btn { float: right; margin-left: 6px; }
.horizon-orphan-container .config-section { padding: 10px 4px; border-bottom: 1px solid #e6e6e6; margin-bottom: 10px; }
.dark-mode .horizon-orphan-container .config-section { border-bottom-color: #3b4d57; }
.horizon-orphan-container .config-row { display: flex; align-items: center; }
.horizon-orphan-container .config-label { font-size: 90%; color: #606266; margin-right: 6px; white-space: nowrap; }
.dark-mode .horizon-orphan-container .config-label { color: #c0c4cc; }
.horizon-orphan-container .keys-header { margin: 2px 0 14px 0; user-select: none; }
.horizon-orphan-container .keys-header .header-title { font-weight: bold; }
.horizon-orphan-container .keys-header .size-header { float: right; margin-left: 10px; min-width: 85px; text-align: right; }
.horizon-orphan-container .keys-header .type-header { float: right; margin-right: 12px; min-width: 60px; text-align: center; }
.horizon-orphan-container .keys-body { height: calc(100vh - 300px); }
.horizon-orphan-container .keys-body li { border-bottom: 1px solid #e6e6e6; cursor: pointer; padding: 0 0 0 4px; margin-right: 2px; font-size: 92%; list-style: none; display: flex; line-height: 24px; }
.dark-mode .horizon-orphan-container .keys-body li { border-bottom: 1px solid #3b4d57; }
.horizon-orphan-container .keys-body li:hover { background: #e6e6e6; }
.dark-mode .horizon-orphan-container .keys-body li:hover { background: #3b4d57; }
.horizon-orphan-container .keys-body li .list-index { min-width: 30px; }
.horizon-orphan-container .keys-body li .key-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.horizon-orphan-container .keys-body li .key-type { min-width: 60px; text-align: center; margin-left: 10px; margin-right: 10px; }
.horizon-orphan-container .keys-body li .size { margin-left: 20px; margin-right: 4px; min-width: 85px; text-align: right; white-space: nowrap; }
.horizon-orphan-container .empty-result { text-align: center; padding: 40px 0; color: #909399; font-size: 110%; }
</style>
