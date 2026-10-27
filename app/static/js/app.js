(() => {
  "use strict";

  const forms = document.querySelectorAll("form[data-loading]");
  forms.forEach((form) => {
    form.querySelectorAll("button[type='submit']").forEach((button) => {
      button.dataset.initiallyDisabled = button.disabled ? "true" : "false";
    });
  });

  const resetForms = () => {
    forms.forEach((form) => {
      delete form.dataset.submitted;
      form.removeAttribute("aria-busy");
      form.querySelectorAll("button[type='submit']").forEach((button) => {
        button.disabled = button.dataset.initiallyDisabled === "true";
        if (button.dataset.originalLabel) {
          button.textContent = button.dataset.originalLabel;
          delete button.dataset.originalLabel;
        }
        button.classList.remove("is-loading");
      });
    });
  };

  forms.forEach((form) => {
    form.addEventListener("submit", (event) => {
      if (form.dataset.submitted === "true") {
        event.preventDefault();
        return;
      }
      if (!form.checkValidity()) {
        return;
      }

      form.dataset.submitted = "true";
      form.setAttribute("aria-busy", "true");

      const button = event.submitter;
      if (button) {
        button.dataset.originalLabel = button.textContent.trim();
        button.textContent = button.dataset.loadingLabel || "Working…";
        button.classList.add("is-loading");
        button.disabled = true;
      }

      // A double submit is blocked while the browser navigates to the result.
      // If the request fails and the page is restored from bfcache, pageshow
      // restores the original button labels and disabled states.
    });
  });

  window.addEventListener("pageshow", resetForms);
})();
