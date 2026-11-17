import { createRouter, createWebHistory } from 'vue-router';
import ShortenerDashboard from '../views/ShortenerDashboard.vue';

const routes = [
  {
    path: '/',
    name: 'dashboard',
    component: ShortenerDashboard
  }
];

const router = createRouter({
  history: createWebHistory(process.env.BASE_URL),
  routes
});

export default router;
