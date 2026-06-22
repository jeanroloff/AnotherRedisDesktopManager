<template>
<div class="horizon-job-filter-container">
  <el-card class="box-card">
    <div slot="header" class="clearfix">
      <span class="analysis-title">
        <i class="fa fa-filter"></i> Horizon Job Filter
      </span>
      <i v-if="isScanning" class="el-icon-loading"></i>
      <el-tag size="mini">Matches: {{matchList.length}}</el-tag>
      <el-tag size="mini" type="info">Scanned: {{scannedCount}}</el-tag>
      <el-tag size="mini" type="success">Total: {{$util.humanFileSize(totalSize)}}</el-tag>
      <el-tag v-if="selectedCount > 0" size="mini" type="danger">Selected: {{selectedCount}}</el-tag>

      <el-button v-if="selectedCount > 0" @click="confirmDeleteSelected" class="operate-btn" type="danger" size="mini" style="margin-right: 8px;">
        <i class="fa fa-trash"></i> Delete Selected
      </el-button>
      <el-tag v-if="memoryCommandDisabled" type="warning" size="mini">MEMORY disabled</el-tag>
      <el-tag v-if="useDumpFallback" type="info" size="mini">~DUMP estimate</el-tag>

      <el-button v-if="scanningEnd" @click="startScan" class="operate-btn" type="primary" size="mini">
        <i class="fa fa-refresh"></i> {{ $t('message.restart') }}
      </el-button>
      <el-button v-else-if="isScanning" @click="toggleScanning(true)" class="operate-btn" type="danger" size="mini">
        <i class="fa fa-pause"></i> {{ $t('message.pause') }}
      </el-button>
      <el-button v-else @click="toggleScanning(false)" class="operate-btn" size="mini">
        <i class="fa fa-play"></i> {{ $t('message.begin') }}
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
        <span class="config-label" style="margin-left: 12px;">Hash Pattern:</span>
        <el-input v-model="hashPattern" size="mini" placeholder="horizon:*" style="width: 200px;"></el-input>
      </div>
      <div v-for="(f, idx) in filters" :key="idx" class="config-row" style="margin-top: 8px;">
        <span class="config-label">Field:</span>
        <el-input v-model="f.field" size="mini" placeholder="queue" style="width: 140px;"></el-input>
        <el-select v-model="f.mode" size="mini" style="width: 110px; margin-left: 6px;">
          <el-option label="Equals" value="equals"></el-option>
          <el-option label="Contains" value="contains"></el-option>
        </el-select>
        <span class="config-label" style="margin-left: 12px;">Value:</span>
        <el-input v-model="f.value" size="mini" placeholder="resizes" style="width: 180px;"></el-input>
        <el-button v-if="filters.length > 1" @click="removeFilter(idx)" type="danger" size="mini" style="margin-left: 6px;">
          <i class="fa fa-minus"></i>
        </el-button>
      </div>
      <div class="config-row" style="margin-top: 8px;">
        <span class="config-label">ZSets:</span>
        <el-input v-model="zsetKeysInput" size="mini" placeholder="horizon:recent_jobs,horizon:failed_jobs" style="width: 400px;"></el-input>
        <el-tooltip content="Comma-separated ZSet keys to remove job entries from">
          <i class="el-icon-question" style="margin-left: 6px; color: #909399;"></i>
        </el-tooltip>
      </div>
      <div class="config-row" style="margin-top: 8px;">
        <el-button @click="addFilter" size="mini">
          <i class="fa fa-plus"></i> Add Filter
        </el-button>
        <el-button @click="startScan" type="primary" size="mini" style="margin-left: 10px;">
          <i class="fa fa-search"></i> Search
        </el-button>
      </div>
    </div>

    <div class="keys-header">
      <span class="header-checkbox">
        <el-checkbox :indeterminate="isIndeterminate" v-model="allSelected" @change="toggleSelectAll"></el-checkbox>
      </span>
      <span class="header-title">
        Key
        <el-tag v-if="activeFilterTag" size="mini">
          <i class="fa fa-filter"></i> {{activeFilterTag}}
        </el-tag>
      </span>
      <span @click="toggleOrder" class="size-container">
        <span class="header-title">Size</span>
        <span class="el-icon-d-caret"></span>
      </span>
      <span class="type-container">
        <span class="header-title">Type</span>
      </span>
    </div>

    <RecycleScroller
      class="keys-body"
      :items="matchList"
      :item-size="28"
      key-field="str"
      v-slot="{ item, index }"
    >
      <li :class="{ selected: item.selected }" @click="clickRow(item, $event)">
        <span class="list-checkbox" @click.stop>
          <el-checkbox v-model="item.selected" @change="onItemSelectChange"></el-checkbox>
        </span>
        <span class="list-index">{{ index + 1 }}.</span>
        <span class="key-name" :title="item.str">{{ item.str }}</span>
        <span class="key-type">
          <el-tag size="mini" type="info">{{ item.type }}</el-tag>
        </span>
        <span class="size">
          <el-tag size="mini" :type="item.tagType || ''" :title="item.errMsg || ''">{{ item.human }}</el-tag>
        </span>
      </li>
    </RecycleScroller>

    <div v-if="matchList.length === 0 && scanningEnd" class="empty-result">
      <i class="fa fa-check-circle" style="color: #67c23a;"></i> No matching jobs found.
    </div>

    <div class="keys-footer">
      <el-tag>Max scan: {{scanMax}}</el-tag>
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
      matchList: [],
      scannedCount: 0,
      preset: 'horizon',
      hashPattern: 'horizon:*',
      filters: [{ field: 'queue', value: '', mode: 'equals' }],
      zsetKeysInput: 'horizon:recent_jobs,horizon:failed_jobs,horizon:completed_jobs,horizon:silenced_jobs',
      allSelected: false,
      isIndeterminate: false,
      scanPageSize: 2000,
      scanMax: 200000,
      sortOrder: 'desc',
      totalSize: 0,
      memoryCommandDisabled: false,
      useDumpFallback: false,
    };
  },
  props: ['client', 'hotKeyScope'],
  components: { RecycleScroller },
  computed: {
    activeFilterTag() {
      const parts = this.filters
        .filter(f => f.field && f.value)
        .map(f => `${f.field}${f.mode === 'contains' ? '~' : '='}${f.value}`);
      return parts.join(', ');
    },
    zsetKeys() {
      return this.zsetKeysInput.split(',').map(s => s.trim()).filter(Boolean);
    },
    selectedCount() {
      return this.matchList.filter(i => i.selected).length;
    },
  },
  methods: {
    addFilter() {
      this.filters.push({ field: '', value: '', mode: 'equals' });
    },
    removeFilter(index) {
      this.filters.splice(index, 1);
    },
    startScan() {
      this.matchList = [];
      this.totalSize = 0;
      this.scannedCount = 0;
      this.scanningEnd = false;
      this.memoryCommandDisabled = false;
      this.useDumpFallback = false;
      this.isScanning = true;
      this.scanStreams = [];
      this.initScanStreamsAndScan();
    },
    applyPreset(val) {
      const presets = {
        horizon: {
          hashPattern: 'horizon:*',
          zsetKeysInput: 'horizon:recent_jobs,horizon:failed_jobs,horizon:completed_jobs,horizon:silenced_jobs',
        },
        brace: {
          hashPattern: '{horizon}:*',
          zsetKeysInput: '{horizon}:recent_jobs,{horizon}:failed_jobs,{horizon}:completed_jobs,{horizon}:silenced_jobs',
        },
      };
      const cfg = presets[val];
      if (cfg) {
        this.hashPattern = cfg.hashPattern;
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
        const promise = this.checkMatch(key).then((result) => {
          if (result && result.matched) {
            this.matchList.push(result);
            this.totalSize += result.size || 0;
            this.reOrder(this.sortOrder);
          }
        });
        allPromise.push(promise);
      }
      return Promise.all(allPromise);
    },
    async checkMatch(key) {
      const keyStr = this.$util.bufToString(key);
      const type = await this.client.call('TYPE', key).catch(() => 'none');
      const typeStr = this.$util.bufToString(type) || 'none';
      if (typeStr !== 'hash') return null;

      const activeFilters = this.filters.filter(f => f.field && f.value);
      if (activeFilters.length === 0) return null;

      for (const f of activeFilters) {
        const fieldValue = await this.client.call('HGET', key, f.field).catch(() => null);
        const fieldValueStr = fieldValue ? this.$util.bufToString(fieldValue) : '';

        let matched = false;
        if (f.mode === 'contains') {
          matched = fieldValueStr.includes(f.value);
        } else {
          matched = fieldValueStr === f.value;
        }
        if (!matched) return null;
      }

      const sizeResult = await this.fetchKeySize(keyStr, 'hash');
      return {
        key,
        str: keyStr,
        size: sizeResult.size,
        human: sizeResult.human,
        type: sizeResult.type,
        isEstimate: sizeResult.isEstimate || false,
        tagType: sizeResult.tagType,
        errMsg: sizeResult.errMsg,
        matched: true,
        selected: false,
      };
    },
    async fetchKeySize(keyStr, knownType) {
      const type = knownType || this.$util.bufToString(await this.client.call('TYPE', keyStr).catch(() => 'none')) || 'none';
      if (type === 'none') {
        return { size: 0, human: 'Missing', type: 'none', tagType: 'warning' };
      }
      try {
        if (this.useDumpFallback) {
          const dumpReply = await this.client.call('DUMP', keyStr);
          if (!dumpReply) {
            return { size: 0, human: 'Missing', type, tagType: 'warning' };
          }
          const size = dumpReply.length;
          return { size, human: `~${this.$util.humanFileSize(size)}`, type, isEstimate: true, tagType: 'info' };
        }
        const reply = await this.client.call('MEMORY', 'USAGE', keyStr);
        if (reply === null || reply === undefined) {
          return { size: 0, human: 'Missing', type, tagType: 'warning' };
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
              return { size: 0, human: 'Missing', type, tagType: 'warning' };
            }
            const size = dumpReply.length;
            return { size, human: `~${this.$util.humanFileSize(size)}`, type, isEstimate: true, tagType: 'info' };
          } catch (dumpErr) {
            return { size: 0, human: 'Err', type, tagType: 'danger', errMsg: rawErr };
          }
        }
        return { size: 0, human: 'Err', type, tagType: 'danger', errMsg: rawErr };
      }
    },
    clickRow(item, event) {
      if (!item || !item.key) return;
      if (event && (event.target.closest('.list-checkbox') || event.target.closest('.el-checkbox'))) {
        return;
      }
      this.$bus.$emit('clickedKey', this.client, item.key, true);
    },
    toggleSelectAll(val) {
      this.matchList.forEach((item) => { item.selected = val; });
      this.isIndeterminate = false;
    },
    onItemSelectChange() {
      const selected = this.matchList.filter(i => i.selected).length;
      this.allSelected = selected === this.matchList.length && this.matchList.length > 0;
      this.isIndeterminate = selected > 0 && selected < this.matchList.length;
    },
    confirmDeleteSelected() {
      const items = this.matchList.filter(i => i.selected);
      this.$confirm(`Delete ${items.length} jobs? This will remove the hash key and try to remove from all configured ZSets.`, 'Confirm Delete', {
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
            const delReply = await this.client.del(item.str);
            deletedKeys += delReply || 0;
          } catch (delErr) {
            console.error('DEL failed for', item.str, delErr.message);
          }
          const member = item.str.startsWith(this.hashPattern.replace('*', '')) ? item.str.slice(this.hashPattern.replace('*', '').length) : item.str;
          for (const zsetKey of this.zsetKeys) {
            try {
              const zremReply = await this.client.call('ZREM', zsetKey, member);
              removedZset += zremReply || 0;
            } catch (zremErr) {
              console.error('ZREM failed for', member, 'in', zsetKey, zremErr.message);
            }
          }
        }
        this.$message.success(`Deleted ${deletedKeys} hash keys, removed ${removedZset} ZSet entries.`);
        const toDelete = new Set(items.map(i => i.str));
        this.matchList = this.matchList.filter(i => !toDelete.has(i.str));
        this.totalSize = this.matchList.reduce((sum, i) => sum + i.size, 0);
        this.onItemSelectChange();
        this.$bus.$emit('refreshKeyList', this.client);
      } catch (e) {
        this.$message.error(`Delete failed: ${e.message}`);
      }
    },
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
    toggleOrder() {
      if (this.isScanning) return;
      this.sortOrder = (this.sortOrder === 'desc' ? 'asc' : 'desc');
      this.reOrder();
    },
    reOrder(order = null) {
      order !== null && (this.sortOrder = order);
      if (this.sortOrder === 'asc') {
        this.matchList.sort((a, b) => a.size - b.size);
      } else {
        this.matchList.sort((a, b) => b.size - a.size);
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
    this.initShortcut();
  },
  beforeDestroy() {
    this.$shortcut.deleteScope(this.hotKeyScope);
    this.toggleScanning(true);
  },
};
</script>

<style>
.horizon-job-filter-container .analysis-title { font-weight: bold; font-size: 120%; }
.horizon-job-filter-container .operate-btn { float: right; margin-left: 6px; }
.horizon-job-filter-container .config-section { padding: 10px 4px; border-bottom: 1px solid #e6e6e6; margin-bottom: 10px; }
.dark-mode .horizon-job-filter-container .config-section { border-bottom-color: #3b4d57; }
.horizon-job-filter-container .config-row { display: flex; align-items: center; }
.horizon-job-filter-container .config-label { font-size: 90%; color: #606266; margin-right: 6px; white-space: nowrap; }
.dark-mode .horizon-job-filter-container .config-label { color: #c0c4cc; }
.horizon-job-filter-container .keys-header { margin: 2px 0 14px 0; user-select: none; display: flex; align-items: center; padding-left: 4px; }
.horizon-job-filter-container .keys-header .header-title { font-weight: bold; }
.horizon-job-filter-container .keys-header .header-checkbox { min-width: 30px; }
.horizon-job-filter-container .keys-header .size-container { float: right; cursor: pointer; }
.horizon-job-filter-container .keys-header .type-container { float: right; margin-right: 12px; }
.horizon-job-filter-container .keys-body { height: calc(100vh - 320px); }
.horizon-job-filter-container .keys-body li { border-bottom: 1px solid #e6e6e6; cursor: pointer; padding: 0 0 0 4px; margin-right: 2px; font-size: 92%; list-style: none; display: flex; line-height: 28px; }
.dark-mode .horizon-job-filter-container .keys-body li { border-bottom: 1px solid #3b4d57; }
.horizon-job-filter-container .keys-body li:hover { background: #e6e6e6; }
.dark-mode .horizon-job-filter-container .keys-body li:hover { background: #3b4d57; }
.horizon-job-filter-container .keys-body li.selected { background: #d9ecff; }
.dark-mode .horizon-job-filter-container .keys-body li.selected { background: #1e3a5f; }
.horizon-job-filter-container .keys-body li .list-checkbox { min-width: 30px; text-align: center; }
.horizon-job-filter-container .keys-body li .list-index { min-width: 30px; }
.horizon-job-filter-container .keys-body li .key-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.horizon-job-filter-container .keys-body .key-type { min-width: 60px; text-align: center; margin-left: 10px; margin-right: 10px; }
.horizon-job-filter-container .keys-body .size { margin-left: 20px; margin-right: 4px; min-width: 85px; text-align: right; white-space: nowrap; }
.horizon-job-filter-container .empty-result { text-align: center; padding: 40px 0; color: #909399; font-size: 110%; }
.horizon-job-filter-container .keys-footer { text-align: center; line-height: 40px; }
</style>
