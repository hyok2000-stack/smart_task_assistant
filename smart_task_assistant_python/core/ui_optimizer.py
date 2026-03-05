"""
UI性能优化模块 - 虚拟滚动、懒加载、渲染优化
"""

import time
from typing import List, Dict, Any, Callable
from PyQt5.QtWidgets import QListWidget, QListWidgetItem, QWidget
from PyQt5.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt5.QtGui import QFont


class VirtualScrollList(QListWidget):
    """虚拟滚动列表 - 只渲染可见项"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        
        self.all_items = []
        self.visible_start = 0
        self.visible_end = 0
        self.item_height = 80
        self.buffer_size = 5
        
        self.verticalScrollBar().valueChanged.connect(self._on_scroll)
        
        self._render_timer = QTimer()
        self._render_timer.setSingleShot(True)
        self._render_timer.timeout.connect(self._render_visible_items)
        
        self._pending_render = False
    
    def set_items(self, items: List[Dict[str, Any]], 
                  item_widget_factory: Callable[[Dict], QWidget]):
        """设置所有数据项"""
        self.clear()
        self.all_items = items
        self.item_widget_factory = item_widget_factory
        
        self.setMinimumHeight(len(items) * self.item_height)
        
        self._update_visible_range()
        self._render_visible_items()
    
    def _on_scroll(self, value):
        """滚动事件处理"""
        self._update_visible_range()
        
        if not self._render_timer.isActive():
            self._render_timer.start(50)
    
    def _update_visible_range(self):
        """更新可见范围"""
        scroll_value = self.verticalScrollBar().value()
        viewport_height = self.viewport().height()
        
        visible_count = viewport_height // self.item_height + 1
        
        self.visible_start = max(0, scroll_value // self.item_height - self.buffer_size)
        self.visible_end = min(
            len(self.all_items),
            self.visible_start + visible_count + self.buffer_size * 2
        )
    
    def _render_visible_items(self):
        """渲染可见项"""
        for i in range(self.visible_start, self.visible_end):
            if i < len(self.all_items):
                item = self.item(i)
                if item is None:
                    list_item = QListWidgetItem()
                    list_item.setSizeHint(Qt.QSize(0, self.item_height))
                    self.insertItem(i, list_item)
                    
                    widget = self.item_widget_factory(self.all_items[i])
                    self.setItemWidget(list_item, widget)
    
    def refresh_item(self, index: int, data: Dict[str, Any]):
        """刷新单个项"""
        if self.visible_start <= index < self.visible_end:
            item = self.item(index)
            if item:
                widget = self.item_widget_factory(data)
                self.setItemWidget(item, widget)


class LazyLoader(QObject):
    """懒加载器"""
    
    data_loaded = pyqtSignal(list)
    loading_started = pyqtSignal()
    loading_finished = pyqtSignal()
    
    def __init__(self, load_function: Callable, batch_size: int = 50):
        super().__init__()
        
        self.load_function = load_function
        self.batch_size = batch_size
        self.current_offset = 0
        self.has_more = True
        self.is_loading = False
        
        self._load_timer = QTimer()
        self._load_timer.setSingleShot(True)
        self._load_timer.timeout.connect(self._do_load)
    
    def load_next_batch(self):
        """加载下一批数据"""
        if self.is_loading or not self.has_more:
            return
        
        self.is_loading = True
        self.loading_started.emit()
        
        self._load_timer.start(10)
    
    def _do_load(self):
        """执行加载"""
        try:
            data = self.load_function(
                offset=self.current_offset,
                limit=self.batch_size
            )
            
            if len(data) < self.batch_size:
                self.has_more = False
            
            self.current_offset += len(data)
            
            self.data_loaded.emit(data)
            
        except Exception as e:
            print(f"Load error: {e}")
        
        finally:
            self.is_loading = False
            self.loading_finished.emit()
    
    def reset(self):
        """重置加载器"""
        self.current_offset = 0
        self.has_more = True
        self.is_loading = False


class RenderOptimizer:
    """渲染优化器"""
    
    def __init__(self):
        self._pending_updates = {}
        self._update_timer = QTimer()
        self._update_timer.setSingleShot(True)
        self._update_timer.timeout.connect(self._apply_pending_updates)
        
        self._batch_size = 10
        self._update_delay = 100
    
    def schedule_update(self, key: str, update_func: Callable, *args, **kwargs):
        """调度更新"""
        self._pending_updates[key] = (update_func, args, kwargs)
        
        if not self._update_timer.isActive():
            self._update_timer.start(self._update_delay)
    
    def _apply_pending_updates(self):
        """应用待处理的更新"""
        updates = list(self._pending_updates.items())
        self._pending_updates.clear()
        
        for key, (func, args, kwargs) in updates:
            try:
                func(*args, **kwargs)
            except Exception as e:
                print(f"Update error for {key}: {e}")
    
    def clear_pending_updates(self):
        """清除待处理的更新"""
        self._pending_updates.clear()
        self._update_timer.stop()


class PerformanceMonitor:
    """性能监控器"""
    
    def __init__(self):
        self.metrics = {}
        self._start_times = {}
    
    def start_operation(self, operation_name: str):
        """开始操作计时"""
        self._start_times[operation_name] = time.time()
    
    def end_operation(self, operation_name: str) -> float:
        """结束操作计时"""
        if operation_name not in self._start_times:
            return 0.0
        
        duration = time.time() - self._start_times[operation_name]
        
        if operation_name not in self.metrics:
            self.metrics[operation_name] = {
                'count': 0,
                'total_time': 0.0,
                'avg_time': 0.0,
                'max_time': 0.0,
                'min_time': float('inf')
            }
        
        metrics = self.metrics[operation_name]
        metrics['count'] += 1
        metrics['total_time'] += duration
        metrics['avg_time'] = metrics['total_time'] / metrics['count']
        metrics['max_time'] = max(metrics['max_time'], duration)
        metrics['min_time'] = min(metrics['min_time'], duration)
        
        del self._start_times[operation_name]
        
        return duration
    
    def get_metrics(self, operation_name: str = None) -> Dict:
        """获取性能指标"""
        if operation_name:
            return self.metrics.get(operation_name, {})
        return self.metrics
    
    def get_report(self) -> str:
        """获取性能报告"""
        lines = ["Performance Report:"]
        lines.append("-" * 60)
        
        for op_name, metrics in self.metrics.items():
            lines.append(f"\n{op_name}:")
            lines.append(f"  Count: {metrics['count']}")
            lines.append(f"  Avg Time: {metrics['avg_time']*1000:.2f}ms")
            lines.append(f"  Max Time: {metrics['max_time']*1000:.2f}ms")
            lines.append(f"  Min Time: {metrics['min_time']*1000:.2f}ms")
        
        return "\n".join(lines)


class WidgetPool:
    """控件池 - 复用控件减少创建开销"""
    
    def __init__(self, widget_factory: Callable, max_size: int = 100):
        self.widget_factory = widget_factory
        self.max_size = max_size
        self._pool = []
        self._in_use = set()
    
    def acquire(self) -> QWidget:
        """获取控件"""
        if self._pool:
            widget = self._pool.pop()
            self._in_use.add(widget)
            return widget
        
        widget = self.widget_factory()
        self._in_use.add(widget)
        return widget
    
    def release(self, widget: QWidget):
        """释放控件"""
        if widget in self._in_use:
            self._in_use.remove(widget)
            
            if len(self._pool) < self.max_size:
                self._pool.append(widget)
            else:
                widget.deleteLater()
    
    def clear(self):
        """清空池"""
        for widget in self._pool:
            widget.deleteLater()
        self._pool.clear()
        
        for widget in self._in_use:
            widget.deleteLater()
        self._in_use.clear()


performance_monitor = PerformanceMonitor()
render_optimizer = RenderOptimizer()
