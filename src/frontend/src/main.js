import { createApp } from 'vue';
import App from './App.vue';
import router from './router';
import store from './store';
import moment from 'moment';
import './assets/main.scss';

const app = createApp(App);
app.use(router);
app.use(store);

// 时间格式化：后端返回 ISO 8601 时间戳
app.config.globalProperties.$formatDate = function (value) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return moment(d).format('YYYY-MM-DD HH:mm:ss');
};

app.mount('#app');
