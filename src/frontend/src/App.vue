<template>
  <div id="app">
    <section class="section">
      <nav
        class="navbar is-fixed-top is-dark"
        role="navigation"
        aria-label="main navigation"
      >
        <div class="navbar-brand">
          <div class="navbar-item">
            <h1 class="title has-text-white">{{ appName }}</h1>
          </div>
          <a
            role="button"
            class="navbar-burger burger"
            aria-label="menu"
            aria-expanded="false"
            data-target="navbarCollapse"
            v-bind:class="{ 'is-active': isOpen }"
            @click="isOpen = !isOpen"
          >
            <span aria-hidden="true"></span>
            <span aria-hidden="true"></span>
            <span aria-hidden="true"></span>
          </a>
        </div>
      </nav>
    </section>
    <section class="section">
      <div class="container">
        <router-view />
      </div>
    </section>
  </div>
</template>

<script>
import { mapState } from "vuex";

export default {
  name: "app",
  data() {
    return {
      appName: process.env.VUE_APP_NAME || "URL Shortener",
      isOpen: false,
    };
  },
  created() {
    // 开放模式：直接进入已授权视图（生产接入自定义认证后再补充登录流程）
    this.$store.commit("authorize");
  },
  computed: {
    ...mapState(["authorized"]),
  },
};
</script>
