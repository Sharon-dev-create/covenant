import { DataNotice } from '../../../components/ui';

export default function Loading() {
  return <main id="main" className="dashboard" tabIndex={-1}><DataNotice kind="loading" /></main>;
}
