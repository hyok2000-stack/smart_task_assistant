import sys
sys.path.insert(0, '.')
from core.database import DatabaseManager

db = DatabaseManager('core/data/tasks.db')
print('Task Stats:', db.get_task_stats())
print('Efficiency Stats:', db.get_efficiency_stats())
print('All Tasks:', len(db.get_all_tasks()))
