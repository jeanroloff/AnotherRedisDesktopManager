<template>
<div class="horizon-heavy-jobs-container">
  <el-card class="box-card">
    <div slot="header" class="clearfix">
      <span class="analysis-title">
        <i class="fa fa-weight-hanging"></i> Horizon Heavy Jobs
      </span>
      <i v-if="isScanning" class="el-icon-loading"></i>
      <el-tag size="mini">Jobs: {{jobList.length}}</el-tag>
      <el-tag v-if="selectedCount > 0" size="mini" type="danger">Selected: {{selectedCount}}</el-tag>
      <el-tag size="mini" type="info">Total Size: {{$util.humanFileSize(totalSize)}}</el-tag>

      <el-button v-if="scanningEnd" @click="startScan" class="operate-btn" type="primary" size="mini">
        <i class="fa fa-refresh"></i> {{ $t('message.restart') }}
      </el-button>
      <el-button v-else-if="isScanning" @click="toggleScanning(true)" class="operate-btn" type="danger" size="mini">
        <i class="fa fa-pause"></i> {{ $t('message.pause') }}
      </el-button>
      <el-button v-else @click="toggleScanning(false)" class="operate-btn" size="mini">
        <i class="fa fa-play"></i> {{ $t('message.begin') }}
      </el-button>
      <el-button v-if="selectedCount > 0" @click="confirmDeleteSelected" class="operate-btn" type="danger" size="mini" style="margin-right: 8px;">
        <i class="fa fa-trash"></i> Delete Selected
      </el-button>
    </div>

    <div class="config-section">
      <div class="config-row">
        <span class="config-label">Preset:</span>
        <el-select v-model="preset" @change="applyPreset" size="mini" style="width: 160px;">
          <el-option label="horizon:" value="horizon"></el-option>
          <el-option label="{horizon}:" value="brace"></el-option>
          <el-option label="Custom" value="custom"></el-option>
        </el-select>
        <span class="config-label" style="margin-left: 12px;">ZSet:</span>
        <el-select v-model="zsetType" @change="onZsetTypeChange" size="mini" style="width: 180px;">
          <el-option label="completed_jobs" value="completed_jobs"></el-option>
          <el-option label="failed_jobs" value="failed_jobs"></el-option>
          <el-option label="recent_jobs" value="recent_jobs"></el-option>
          <el-option label="silenced_jobs" value="silenced_jobs"></el-option>
          <el-option label="Custom" value="custom"></el-option>
        </el-select>
      </div>
      <div class="config-row" style="margin-top: 8px;">
        <span class="config-label">ZSet Key:</span>
        <el-input v-model="zsetKey" size="mini" placeholder="horizon:completed_jobs" style="width: 220px;"></el-input>
        <span class="config-label" style="margin-left: 12px;">Hash Prefix:</span>
        <el-input v-model="hashPrefix" size="mini" placeholder="horizon:" style="width: 200px;"></el-input>
        <span class="config-label" style="margin-left: 12px;">Min Size:</span>
        <el-input v-model="minSizeKB" size="mini" style="width: 80px;">
          <i slot="suffix">KB</i>
        </el-input>
        <el-button @click="testSample" size="mini" style="margin-left: 10px;">
          <i class="fa fa-vial"></i> Test Sample
        </el-button>
      </div>
      <div v-if="sampleDebug" class="config-row" style="margin-top: 8px; font-size: 90%; color: #909399;">
        <pre style="margin: 0; background: #f5f7fa; padding: 6px; border-radius: 3px; max-height: 120px; overflow-y: auto;">{{ sampleDebug }}</pre>
      </div>
    </div>

    <div class="keys-header">
      <span class="header-checkbox">
        <el-checkbox :indeterminate="isIndeterminate" v-model="allSelected" @change="toggleSelectAll"></el-checkbox>
      </span>
      <span class="header-title">Job ID / Hash Key</span>
      <span class="header-title score-header">Score</span>
      <span class="header-title size-header">Size</span>
      <span class="header-title type-header">Type</span>
    </div>

    <RecycleScroller class="keys-body" :items="jobList" :item-size="28" key-field="member" v-slot="{ item, index }">
      <li :class="{ selected: item.selected }" @click="clickRow(item, $event)">
        <span class="list-checkbox" @click.stop>
          <el-checkbox v-model="item.selected" @change="onItemSelectChange"></el-checkbox>
        </span>
        <span class="key-name" :title="item.hashKeyStr">
          <span class="member-id">{{ item.member }}</span>
          <span class="hash-arrow">→</span>
          <span class="hash-key">{{ item.hashKeyStr }}</span>
        </span>
        <span class="score">{{ item.scoreDate }}</span>
        <span class="size">
          <el-tag size="mini" :type="item.tagType || ''" :title="item.errMsg || ''">{{ item.human }}</el-tag>
        </span>
        <span class="key-type">
          <el-tag size="mini" type="info">{{ item.type }}</el-tag>
        </span>
      </li>
    </RecycleScroller>

    <div v-if="jobList.length === 0 && scanningEnd" class="empty-result">
      <i class="fa fa-check-circle" style="color: #67c23a;"></i> No jobs found in this ZSet.
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
      jobList: [],
      totalSize: 0,
      preset: 'horizon',
      zsetType: 'completed_jobs',
      zsetKey: 'horizon:completed_jobs',
      hashPrefix: 'horizon:',
      minSizeKB: 0,
      scanOffset: 0,
      scanBatchSize: 500,
      scanMax: 50000,
      allSelected: false,
      isIndeterminate: false,
      useDumpFallback: false,
      memoryCommandDisabled: false,
      sampleDebug: '',
    };
  },
  props: ['client', 'hotKeyScope'],
  components: { RecycleScroller },
  computed: {
    minSizeB() {
      return parseInt(this.minSizeKB) * 1024;
    },
    selectedCount() {
      return this.jobList.filter(i => i.selected).length;
    },
  },
  watch: {
    zsetType(val) {
      if (val !== 'custom') {
        this.zsetKey = this.buildZsetKey(val);
      }
    },
  },
  methods: {
    buildZsetKey(type) {
      const base = this.preset === 'brace' ? '{horizon}' : 'horizon';
      return `${base}:${type}`;
    },
    onZsetTypeChange(val) {
      if (val !== 'custom') {
        this.zsetKey = this.buildZsetKey(val);
      }
    },
    applyPreset(val) {
      const presets = {
        horizon: { hashPrefix: 'horizon:' },
        brace: { hashPrefix: '{horizon}:' },
      };
      const cfg = presets[val];
      if (cfg) {
        this.hashPrefix = cfg.hashPrefix;
        if (this.zsetType !== 'custom') {
          this.zsetKey = this.buildZsetKey(this.zsetType);
        }
      }
    },
    async testSample() {
      try {
        const sample = await this.client.call('ZRANGE', this.zsetKey, 0, 0);
        if (!sample || sample.length === 0) {
          this.sampleDebug = 'ZSet is empty.';
          return;
        }
        const member = this.$util.bufToString(sample[0]);
        const tests = [
          this.hashPrefix + member,
          'horizon:' + member,
          '{horizon}:' + member,
          'horizon:job:' + member,
          '{horizon}:job:' + member,
        ];
        const lines = [`ZSet: ${this.zsetKey}`, `Member: ${member}`, '---'];
        for (const key of [...new Set(tests)]) {
          try {
            const typeRaw = await this.client.call('TYPE', key);
            const type = this.$util.bufToString(typeRaw) || 'none';
            const exists = await this.client.call('EXISTS', key);
            const existsVal = parseInt(this.$util.bufToString(exists) || '0', 10);
            lines.push(`Key: ${key}  =>  type=${type}, exists=${existsVal}`);
          } catch (e) {
            lines.push(`Key: ${key}  =>  ERROR: ${e.message}`);
          }
        }
        this.sampleDebug = lines.join('\n');
      } catch (e) {
        this.sampleDebug = `Error: ${e.message}`;
      }
    },
    startScan() {
      this.jobList = [];
      this.totalSize = 0;
      this.scanOffset = 0;
      this.isScanning = true;
      this.scanningEnd = false;
      this.allSelected = false;
      this.isIndeterminate = false;
      this.useDumpFallback = false;
      this.memoryCommandDisabled = false;
      this.scanBatch();
    },
    async scanBatch() {
      if (!this.isScanning) return;
      if (this.scanOffset >= this.scanMax) {
        this.$message.warning(`Reached max scan limit (${this.scanMax}), stopped.`);
        this.isScanning = false;
        this.scanningEnd = true;
        return;
      }
      try {
        const entries = await this.client.call('ZRANGE', this.zsetKey, this.scanOffset, this.scanOffset + this.scanBatchSize - 1, 'WITHSCORES');
        if (!entries || entries.length === 0) {
          this.isScanning = false;
          this.scanningEnd = true;
          return;
        }
        const batch = [];
        for (let i = 0; i < entries.length; i += 2) {
          const member = this.$util.bufToString(entries[i]);
          const score = parseFloat(this.$util.bufToString(entries[i + 1]));
          batch.push({ member, score });
        }
        this.scanOffset += batch.length;
        await this.processBatch(batch);
        if (this.isScanning) {
          setTimeout(() => this.scanBatch(), 10);
        }
      } catch (e) {
        this.$message.error(`Scan Error: ${e.message}`);
        this.isScanning = false;
        this.scanningEnd = true;
      }
    },
    async processBatch(batch) {
      const allPromise = [];
      for (const entry of batch) {
        const promise = this.analyzeJob(entry).then((result) => {
          if (!result) return;
          if (this.minSizeB && result.size < this.minSizeB) return;
          this.jobList.push(result);
          this.totalSize += result.size;
        });
        allPromise.push(promise);
      }
      await Promise.all(allPromise);
      this.jobList.sort((a, b) => b.size - a.size);
    },
    async analyzeJob({ member, score }) {
      const hashKeyStr = this.hashPrefix + member;
      const hashKey = Buffer.from(hashKeyStr);
      const typeRaw = await this.client.call('TYPE', hashKeyStr).catch(() => 'none');
      const type = this.$util.bufToString(typeRaw) || 'none';
      if (type === 'none') {
        return {
          member,
          score,
          scoreDate: this.formatScore(score),
          hashKey,
          hashKeyStr,
          size: 0,
          human: 'Missing',
          type: 'none',
          tagType: 'warning',
          selected: false,
        };
      }
      const sizeResult = await this.fetchKeySize(hashKeyStr, type);
      return {
        member,
        score,
        scoreDate: this.formatScore(score),
        hashKey,
        hashKeyStr,
        size: sizeResult.size,
        human: sizeResult.human,
        type: sizeResult.type,
        tagType: sizeResult.tagType,
        errMsg: sizeResult.errMsg,
        selected: false,
      };
    },
    async fetchKeySize(keyStr, knownType) {
      const type = knownType || this.$util.bufToString(await this.client.call('TYPE', keyStr).catch(() => 'none')) || 'none';
      if (type === 'none') {
        return {
          size: 0, human: 'Missing', type: 'none', tagType: 'warning',
        };
      }
      try {
        if (this.useDumpFallback) {
          const dumpReply = await this.client.call('DUMP', keyStr);
          if (!dumpReply) {
            return {
              size: 0, human: 'Missing', type, tagType: 'warning',
            };
          }
          const size = dumpReply.length;
          return {
            size, human: `~${this.$util.humanFileSize(size)}`, type, isEstimate: true,
          };
        }
        const reply = await this.client.call('MEMORY', 'USAGE', keyStr);
        if (reply === null || reply === undefined) {
          return {
            size: 0, human: 'Missing', type, tagType: 'warning',
          };
        }
        const size = parseInt(reply, 10) || 0;
        return { size, human: this.$util.humanFileSize(size), type };
      } catch (e) {
        const rawErr = (e && e.message) ? e.message : '';
        const errMsg = rawErr.toLowerCase();
        const isBlocked = errMsg.includes('unknown command') || errMsg.includes('disabled') || errMsg.includes('not supported') || errMsg.includes('noperm') || errMsg.includes('memory|usage') || errMsg.includes("no permissions to run the 'memory");
        if (isBlocked && !this.memoryCommandDisabled) {
          this.memoryCommandDisabled = true;
          this.useDumpFallback = true;
          this.$message.warning('MEMORY command disabled, falling back to DUMP size estimation.');
          return this.fetchKeySize(keyStr, type);
        }
        if (this.useDumpFallback) {
          try {
            const dumpReply = await this.client.call('DUMP', keyStr);
            if (!dumpReply) {
              return {
                size: 0, human: 'Missing', type, tagType: 'warning',
              };
            }
            const size = dumpReply.length;
            return {
              size, human: `~${this.$util.humanFileSize(size)}`, type, isEstimate: true, tagType: 'info',
            };
          } catch (dumpErr) {
            return {
              size: 0, human: 'Err', type, tagType: 'danger', errMsg: rawErr,
            };
          }
        }
        return {
          size: 0, human: 'Err', type, tagType: 'danger', errMsg: rawErr,
        };
      }
    },
    formatScore(score) {
      if (!score || score <= 0) return '-';
      const date = new Date(score * 1000);
      if (isNaN(date.getTime())) return String(score);
      return date.toISOString().replace('T', ' ').substring(0, 19);
    },
    clickRow(item, event) {
      if (!item || !item.hashKey) return;
      if (event && (event.target.closest('.list-checkbox') || event.target.closest('.el-checkbox'))) {
        return;
      }
      this.$bus.$emit('clickedKey', this.client, item.hashKey, true);
    },
    toggleScanning(pause = true) {
      if (pause) {
        this.isScanning = false;
        return;
      }
      if (this.scanningEnd) return;
      this.isScanning = true;
      this.scanBatch();
    },
    toggleSelectAll(val) {
      this.jobList.forEach((item) => { item.selected = val; });
      this.isIndeterminate = false;
    },
    onItemSelectChange() {
      const selected = this.jobList.filter(i => i.selected).length;
      this.allSelected = selected === this.jobList.length && this.jobList.length > 0;
      this.isIndeterminate = selected > 0 && selected < this.jobList.length;
    },
    confirmDeleteSelected() {
      const items = this.jobList.filter(i => i.selected);
      this.$confirm(`Delete ${items.length} jobs? This will remove both the hash key and the ZSet entry.`, 'Confirm Delete', {
        type: 'warning', confirmButtonText: 'Delete', confirmButtonClass: 'el-button--danger',
      }).then(() => this.deleteSelected(items)).catch(() => {});
    },
    async deleteSelected(items) {
      if (!items || items.length === 0) return;
      this.$message.info(`Deleting ${items.length} jobs...`);
      let deletedKeys = 0;
      let removedZset = 0;
      try {
        for (const item of items) {
          try {
            const delReply = await this.client.del(item.hashKeyStr);
            deletedKeys += delReply || 0;
          } catch (delErr) {
            console.error('DEL failed for', item.hashKeyStr, delErr.message);
          }
          try {
            const zremReply = await this.client.call('ZREM', this.zsetKey, item.member);
            removedZset += zremReply || 0;
          } catch (zremErr) {
            console.error('ZREM failed for', item.member, zremErr.message);
          }
        }
        this.$message.success(`Deleted ${deletedKeys} hash keys, removed ${removedZset} ZSet entries.`);
        // remove from local list
        const toDelete = new Set(items.map(i => i.member));
        this.jobList = this.jobList.filter(i => !toDelete.has(i.member));
        this.totalSize = this.jobList.reduce((sum, i) => sum + i.size, 0);
        this.onItemSelectChange();
        this.$bus.$emit('refreshKeyList', this.client);
      } catch (e) {
        this.$message.error(`Delete failed: ${e.message}`);
      }
    },
    initShortcut() {
      this.$shortcut.bind('ctrl+r, ⌘+r, f5', this.hotKeyScope, () => {
        if (!this.scanningEnd) return false;
        this.startScan();
        return false;
      });
    },
  },
  mounted() {
    this.startScan();
    this.initShortcut();
  },
  beforeDestroy() {
    this.$shortcut.deleteScope(this.hotKeyScope);
    this.isScanning = false;
  },
};
</script>

<style>
.horizon-heavy-jobs-container .analysis-title { font-weight: bold; font-size: 120%; }
.horizon-heavy-jobs-container .operate-btn { float: right; margin-left: 6px; }
.horizon-heavy-jobs-container .config-section { padding: 10px 4px; border-bottom: 1px solid #e6e6e6; margin-bottom: 10px; }
.dark-mode .horizon-heavy-jobs-container .config-section { border-bottom-color: #3b4d57; }
.horizon-heavy-jobs-container .config-row { display: flex; align-items: center; flex-wrap: wrap; }
.horizon-heavy-jobs-container .config-label { font-size: 90%; color: #606266; margin-right: 6px; white-space: nowrap; }
.dark-mode .horizon-heavy-jobs-container .config-label { color: #c0c4cc; }

.horizon-heavy-jobs-container .keys-header {
  margin: 2px 0 14px 0; user-select: none; display: flex; align-items: center; padding-left: 4px;
}
.horizon-heavy-jobs-container .keys-header .header-title { font-weight: bold; }
.horizon-heavy-jobs-container .keys-header .header-checkbox { min-width: 30px; }
.horizon-heavy-jobs-container .keys-header .size-header { min-width: 90px; text-align: right; margin-left: 10px; }
.horizon-heavy-jobs-container .keys-header .score-header { min-width: 130px; text-align: center; margin-left: 10px; }
.horizon-heavy-jobs-container .keys-header .type-header { min-width: 60px; text-align: center; margin-right: 4px; }

.horizon-heavy-jobs-container .keys-body { height: calc(100vh - 300px); }
.horizon-heavy-jobs-container .keys-body li {
  border-bottom: 1px solid #e6e6e6; cursor: pointer; padding: 0 0 0 4px; margin-right: 2px;
  font-size: 92%; list-style: none; display: flex; align-items: center; line-height: 28px;
}
.dark-mode .horizon-heavy-jobs-container .keys-body li { border-bottom: 1px solid #3b4d57; }
.horizon-heavy-jobs-container .keys-body li:hover { background: #e6e6e6; }
.dark-mode .horizon-heavy-jobs-container .keys-body li:hover { background: #3b4d57; }
.horizon-heavy-jobs-container .keys-body li.selected { background: #d9ecff; }
.dark-mode .horizon-heavy-jobs-container .keys-body li.selected { background: #1e3a5f; }

.horizon-heavy-jobs-container .keys-body li .list-checkbox { min-width: 30px; text-align: center; }
.horizon-heavy-jobs-container .keys-body li .key-name {
  flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: flex; align-items: center;
}
.horizon-heavy-jobs-container .keys-body li .key-name .member-id { font-weight: bold; color: #409eff; }
.horizon-heavy-jobs-container .keys-body li .key-name .hash-arrow { margin: 0 6px; color: #909399; font-size: 90%; }
.horizon-heavy-jobs-container .keys-body li .key-name .hash-key { color: #606266; }
.dark-mode .horizon-heavy-jobs-container .keys-body li .key-name .hash-key { color: #c0c4cc; }
.horizon-heavy-jobs-container .keys-body li .score { min-width: 130px; text-align: center; margin-left: 10px; font-size: 90%; color: #909399; }
.horizon-heavy-jobs-container .keys-body li .size { margin-left: 10px; margin-right: 4px; min-width: 90px; text-align: right; white-space: nowrap; }
.horizon-heavy-jobs-container .keys-body li .key-type { min-width: 60px; text-align: center; margin-left: 10px; margin-right: 4px; }
.horizon-heavy-jobs-container .empty-result { text-align: center; padding: 40px 0; color: #909399; font-size: 110%; }
</style>
