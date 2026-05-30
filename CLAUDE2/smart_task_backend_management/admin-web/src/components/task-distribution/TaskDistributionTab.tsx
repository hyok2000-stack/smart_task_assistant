import { useEffect, useState } from 'react';
import type { Overview, TaskDistribution } from '../../types';
import * as api from '../../api';
import DistributionForm from './DistributionForm';
import DistributionTable from './DistributionTable';

interface TaskDistributionTabProps {
  overview: Overview;
  adminUserId: string;
  token: string;
  onRefresh: () => void;
}

export default function TaskDistributionTab({ overview, adminUserId, token, onRefresh }: TaskDistributionTabProps) {
  const [distributions, setDistributions] = useState<TaskDistribution[]>([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const pageSize = 20;

  const loadDistributions = async (p: number) => {
    try {
      const result = await api.loadAdminDistributions(token, { page: p, pageSize });
      setDistributions(result.distributions);
      setPage(result.page);
      setTotalPages(result.totalPages);
      setTotal(result.total);
    } catch (e) {
      console.error('Failed to load distributions:', e);
    }
  };

  useEffect(() => {
    loadDistributions(1);
  }, [token]);

  const handlePageChange = (newPage: number) => {
    loadDistributions(newPage);
  };

  const handleSuccess = () => {
    loadDistributions(1);
    onRefresh();
  };

  return (
    <div className="tab-content">
      <div className="panel">
        <DistributionForm
          initialTasks={overview.tasks}
          teams={overview.teams}
          adminUserId={adminUserId}
          token={token}
          onSuccess={handleSuccess}
        />
      </div>

      <div className="panel">
        <h2>分发记录</h2>
        <DistributionTable
          distributions={distributions}
          users={overview.users}
          page={page}
          totalPages={totalPages}
          total={total}
          onPageChange={handlePageChange}
        />
      </div>
    </div>
  );
}
